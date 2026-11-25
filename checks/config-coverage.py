#!/usr/bin/env python3
"""Check that typed NixOS module options cover the pinned upstream config.

The modules render three TOML files from typed options:

  * vpn.toml    - services.trusttunnel.endpoint (main settings)
  * hosts.toml  - services.trusttunnel.endpoint.tls (TLS hosts)
  * config.toml - services.trusttunnel.client

The upstream endpoint (Rust) and the upstream client configuration (also Rust)
both describe their configuration as serde structs. This script parses those
structs at the pinned revisions, flattens the accepted keys into dotted paths,
and compares them with the keys emitted by a module configuration that sets
every typed option. It exits non-zero when an upstream key has no typed option.

The client binary is C++ and its hand-written parser additionally accepts a few
keys that the Rust client configuration model does not describe (`netns`,
`ssl_session_cache_path`, and a legacy top-level `dns_upstreams`). They are not
covered here because they have no serde definition to parse.

The endpoint credentials and rules files and the client credentials file are
separate, user-provided side files, so they are outside this comparison.

The comparison is bidirectional: keys emitted by the typed options but unknown
to upstream are reported as well, because such an option silently does nothing.
Freeform escapes (`settings`, `extraConfig`, ...) are intentionally empty in the
probe configuration, so every emitted key comes from a typed option.

Keys that upstream accepts but that are intentionally not typed are recorded in
ALLOWED_MISSING with a reason.
"""

from __future__ import annotations

import re
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

# Sentinel for a scalar value. Only the presence of the key matters.
LEAF = ("leaf",)

# A typed option that renders a TOML path is intentionally absent up here.
# Keep entries specific and explain why a typed option would be wrong.
ALLOWED_MISSING = {
    (
        "hosts.toml",
        "ping_hosts[].allowed_sni",
    ): "TlsHostInfo carries allowed_sni for every host kind, but the endpoint "
    "only applies it to main_hosts, so a typed ping-host option would be inert",
    (
        "hosts.toml",
        "speedtest_hosts[].allowed_sni",
    ): "TlsHostInfo carries allowed_sni for every host kind, but the endpoint "
    "only applies it to main_hosts, so a typed speedtest-host option would be inert",
    (
        "config.toml",
        "endpoint.name",
    ): "the client service ignores endpoint.name; the setup wizard only uses it "
    "when exporting a deep-link",
}


# ---------------------------------------------------------------------------
# Rust serde struct extraction
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Field:
    name: str
    key: str
    ty: str
    recurse: bool


@dataclass
class Struct:
    name: str
    fields: list[Field]


@dataclass
class Enum:
    name: str
    variants: list[tuple[str, str | None]]


_STRUCT_RE = re.compile(r"^(?:pub(?:\([^)]*\))?\s+)?struct\s+([A-Za-z_]\w*)\b")
_ENUM_RE = re.compile(r"^(?:pub(?:\([^)]*\))?\s+)?enum\s+([A-Za-z_]\w*)\b")
_FIELD_RE = re.compile(
    r"^(?:pub(?:\([^)]*\))?\s+)?(?P<name>[A-Za-z_]\w*)\s*:\s*(?P<ty>.+?)\s*,?\s*$"
)
_VARIANT_RE = re.compile(r"^(?P<name>[A-Za-z_]\w*)(?:\((?P<ty>[^)]*)\))?$")
_SKIP_RE = re.compile(r"\bskip\b")


def _take_attribute(lines: list[str], i: int) -> tuple[str, int]:
    """Consume `#[...]`, which may span several lines."""
    depth = 0
    parts = []
    while i < len(lines):
        line = lines[i]
        parts.append(line.strip())
        depth += line.count("[") - line.count("]")
        i += 1
        if depth <= 0:
            break
    return " ".join(parts), i


def _take_block(lines: list[str], i: int) -> tuple[str, int]:
    """Return the body of a `struct`/`enum` whose opening brace is on line i."""
    line = lines[i]
    brace = line.find("{")
    if brace == -1:
        # A unit struct such as `struct Marker;`.
        return "", i + 1

    rest = line[brace + 1 :]
    end = rest.find("}")
    if end != -1:
        return rest[:end], i + 1

    body = [rest] if rest.strip() else []
    j = i + 1
    while j < len(lines):
        stripped = lines[j].strip()
        # Field types never contain braces, so the first bare closing brace
        # ends the body. Doc comments keep their `///` prefix.
        if stripped == "}" or stripped.startswith("}"):
            return "\n".join(body), j + 1
        body.append(lines[j])
        j += 1
    raise ValueError(f"unterminated block starting at line {i + 1}")


def _rename_all(attributes: list[str]) -> str | None:
    for attribute in attributes:
        match = re.search(r'rename_all\s*=\s*"([^"]+)"', attribute)
        if match:
            return match.group(1)
    return None


def _snake_case(name: str) -> str:
    first = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", first).lower()


def _apply_case(name: str, rename_all: str | None) -> str:
    if rename_all == "snake_case":
        return _snake_case(name)
    if rename_all == "kebab-case":
        return _snake_case(name).replace("_", "-")
    if rename_all == "lowercase":
        return name.lower()
    if rename_all == "UPPERCASE":
        return name.upper()
    return name


def _field_key(name: str, attributes: str, rename_all: str | None) -> str:
    match = re.search(r'rename\([^)]*deserialize\s*=\s*"([^"]+)"', attributes)
    if match:
        return match.group(1)
    match = re.search(r'\brename\s*=\s*"([^"]+)"', attributes)
    if match:
        return match.group(1)
    return _apply_case(name, rename_all)


def _parse_struct(name: str, body: str, outer: list[str]) -> Struct:
    rename_all = _rename_all(outer)
    fields: list[Field] = []
    pending: list[str] = []
    lines = body.splitlines()

    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if not stripped:
            i += 1
            continue
        if stripped.startswith("#["):
            attribute, i = _take_attribute(lines, i)
            pending.append(attribute)
            continue
        if stripped.startswith("//") or stripped.startswith("/*"):
            i += 1
            continue

        match = _FIELD_RE.match(stripped)
        if match:
            attributes = " ".join(pending)
            if not _SKIP_RE.search(attributes):
                fields.append(
                    Field(
                        name=match.group("name"),
                        key=_field_key(match.group("name"), attributes, rename_all),
                        ty=match.group("ty").strip(),
                        # A custom deserializer may turn a container type into a
                        # scalar (for example `Vec<Client>` -> `credentials_file`).
                        recurse="deserialize_with" not in attributes,
                    )
                )
            pending = []
            i += 1
            continue

        pending = []
        i += 1

    return Struct(name, fields)


def _parse_enum(name: str, body: str, outer: list[str]) -> Enum:
    rename_all = _rename_all(outer)
    variants: list[tuple[str, str | None]] = []

    for line in body.splitlines():
        stripped = line.strip().rstrip(",").strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("#["):
            continue
        match = _VARIANT_RE.match(stripped)
        if match:
            inner = match.group("ty")
            variants.append(
                (
                    _apply_case(match.group("name"), rename_all),
                    inner.strip() if inner else None,
                )
            )

    return Enum(name, variants)


def parse_rust(source: Path) -> tuple[dict[str, Struct], dict[str, Enum]]:
    structs: dict[str, Struct] = {}
    enums: dict[str, Enum] = {}
    lines = source.read_text().splitlines()

    pending: list[str] = []
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if not stripped:
            i += 1
            continue
        if stripped.startswith("#["):
            attribute, i = _take_attribute(lines, i)
            pending.append(attribute)
            continue
        if stripped.startswith("//") or stripped.startswith("/*"):
            i += 1
            continue

        match = _STRUCT_RE.match(stripped)
        if match:
            body, i = _take_block(lines, i)
            structs.setdefault(match.group(1), _parse_struct(match.group(1), body, pending))
            pending = []
            continue

        match = _ENUM_RE.match(stripped)
        if match:
            body, i = _take_block(lines, i)
            enums.setdefault(match.group(1), _parse_enum(match.group(1), body, pending))
            pending = []
            continue

        pending = []
        i += 1

    return structs, enums


# ---------------------------------------------------------------------------
# Schema expansion and flattening
# ---------------------------------------------------------------------------


@dataclass
class RustSource:
    paths: list[Path]
    structs: dict[str, Struct] = field(default_factory=dict)
    enums: dict[str, Enum] = field(default_factory=dict)

    def __post_init__(self) -> None:
        for path in self.paths:
            structs, enums = parse_rust(path)
            self.structs.update(structs)
            self.enums.update(enums)

    def tree(self, root: str) -> tuple:
        return self._expand(root, seen=())

    def _expand(self, ty: str, seen: tuple[str, ...]) -> tuple:
        ty = ty.strip()
        if ty.startswith("Option<") and ty.endswith(">"):
            return self._expand(ty[len("Option<") : -1], seen)
        if ty.startswith("Vec<") and ty.endswith(">"):
            return ("list", self._expand(ty[len("Vec<") : -1], seen))
        if ty in seen:
            return LEAF

        struct = self.structs.get(ty)
        if struct is not None:
            nested = seen + (ty,)
            fields = {}
            for member in struct.fields:
                fields[member.key] = (
                    self._expand(member.ty, nested) if member.recurse else LEAF
                )
            return ("table", fields)

        enum = self.enums.get(ty)
        if enum is not None:
            nested = seen + (ty,)
            variants = {}
            for key, inner in enum.variants:
                variants[key] = self._expand(inner, nested) if inner else LEAF
            return ("enum", variants)

        return LEAF


def flatten(node: tuple, prefix: str, out: set[str]) -> None:
    kind = node[0]
    if kind == "leaf":
        if prefix:
            out.add(prefix)
        return

    if prefix:
        out.add(prefix)

    if kind in ("table", "enum"):
        for key, child in node[1].items():
            flatten(child, f"{prefix}.{key}" if prefix else key, out)
    elif kind == "list":
        item = node[1]
        if item[0] != "leaf":
            flatten(item, f"{prefix}[]" if prefix else "[]", out)
    else:  # pragma: no cover - defensive
        raise ValueError(f"unknown node kind {kind!r}")


def toml_node(value: object) -> tuple:
    if isinstance(value, dict):
        return ("table", {key: toml_node(child) for key, child in value.items()})
    if isinstance(value, list):
        if value and all(isinstance(item, dict) for item in value):
            merged: dict[str, tuple] = {}
            for item in value:
                node = toml_node(item)
                assert node[0] == "table"
                merged.update(node[1])
            return ("list", ("table", merged))
        return LEAF
    return LEAF


# ---------------------------------------------------------------------------
# Check
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Target:
    name: str
    source: str
    root: str


TARGETS = [
    Target("vpn.toml", "endpoint", "Settings"),
    Target("hosts.toml", "endpoint", "TlsHostsSettings"),
    Target("config.toml", "client", "Settings"),
]


def main() -> int:
    if len(sys.argv) != 6:
        print(
            "usage: config-coverage.py <endpoint-src> <client-src> "
            "<vpn.toml> <hosts.toml> <config.toml>",
            file=sys.stderr,
        )
        return 2

    endpoint_src = Path(sys.argv[1])
    client_src = Path(sys.argv[2])
    configs = {
        "vpn.toml": Path(sys.argv[3]),
        "hosts.toml": Path(sys.argv[4]),
        "config.toml": Path(sys.argv[5]),
    }

    sources = {
        "endpoint": RustSource(
            [
                endpoint_src / "lib/src/settings.rs",
                endpoint_src / "lib/src/subscription.rs",
            ]
        ),
        "client": RustSource(
            [
                client_src / "trusttunnel/setup_wizard/src/settings.rs",
                client_src / "trusttunnel/settings/src/lib.rs",
            ]
        ),
    }

    upstream_by_target: dict[str, set[str]] = {}
    emitted_by_target: dict[str, set[str]] = {}
    for target in TARGETS:
        upstream: set[str] = set()
        flatten(sources[target.source].tree(target.root), "", upstream)
        upstream_by_target[target.name] = upstream

        emitted: set[str] = set()
        flatten(toml_node(tomllib.loads(configs[target.name].read_text())), "", emitted)
        emitted_by_target[target.name] = emitted

    used_allowlist: set[tuple[str, str]] = set()
    failures: list[str] = []
    for target in TARGETS:
        upstream = upstream_by_target[target.name]
        emitted = emitted_by_target[target.name]

        missing = []
        for key in sorted(upstream - emitted):
            if (target.name, key) in ALLOWED_MISSING:
                used_allowlist.add((target.name, key))
            else:
                missing.append(key)
        extra = sorted(emitted - upstream)

        if missing:
            failures.append(
                f"{target.name}: upstream keys with no typed option:\n"
                + "\n".join(f"  - {key}" for key in missing)
            )
        if extra:
            failures.append(
                f"{target.name}: typed options emit keys that upstream does not accept:\n"
                + "\n".join(f"  - {key}" for key in extra)
            )

    stale = sorted(set(ALLOWED_MISSING) - used_allowlist)
    if stale:
        failures.append(
            "stale ALLOWED_MISSING entries (the key is now covered or no longer exists):\n"
            + "\n".join(f"  - {target}: {key}" for target, key in stale)
        )

    if failures:
        print("config-coverage: typed options do not match the pinned upstream config.")
        print()
        print("\n\n".join(failures))
        print()
        print(
            "Add or adjust typed options in modules/*.nix. If a key is intentionally\n"
            "not typed, add it to ALLOWED_MISSING in checks/config-coverage.py with a\n"
            "reason. If upstream ignores a key that a typed option still emits, remove\n"
            "the option or stop emitting the key."
        )
        return 1

    total = sum(len(keys) for keys in upstream_by_target.values())
    print(
        f"config-coverage: {total} upstream config keys accounted for "
        f"({len(ALLOWED_MISSING)} intentional exceptions)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

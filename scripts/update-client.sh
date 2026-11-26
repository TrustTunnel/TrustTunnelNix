#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash curl jq nix python3

set -euo pipefail

repo="TrustTunnel/TrustTunnelClient"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_file="${script_dir}/../pkgs/trusttunnel-client.nix"

if [[ "${1:-}" == "--version" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "usage: $0 [--version X.Y.Z]" >&2
    exit 2
  fi
  version="$2"
  tag="v${version}"
else
  curl_args=(-fsSL)
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  release="$(curl "${curl_args[@]}" "https://api.github.com/repos/${repo}/releases/latest")"
  tag="$(jq -r '.tag_name' <<<"$release")"
  version="${tag#v}"
fi

base="https://github.com/${repo}/releases/download/${tag}"

hash_for() {
  nix store prefetch-file --json "$1" | jq -r '.hash'
}

x86_64_linux="$(hash_for "${base}/trusttunnel_client-v${version}-linux-x86_64.tar.gz")"
aarch64_linux="$(hash_for "${base}/trusttunnel_client-v${version}-linux-aarch64.tar.gz")"
macos="$(hash_for "${base}/trusttunnel_client-v${version}-macos-universal.tar.gz")"
client_src="$(nix store prefetch-file --unpack --json "https://github.com/${repo}/archive/refs/tags/${tag}.tar.gz" | jq -r '.hash')"

python3 - "$package_file" "$version" "$x86_64_linux" "$aarch64_linux" "$macos" "$client_src" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
version, x86_64_linux, aarch64_linux, macos, client_src = sys.argv[2:7]
text = path.read_text()

text, count = re.subn(r'version = "[^"]+";', f'version = "{version}";', text, count=1)
if count != 1:
    raise SystemExit("failed to update version")

for system, digest in (
    ("x86_64-linux", x86_64_linux),
    ("aarch64-linux", aarch64_linux),
    ("x86_64-darwin", macos),
    ("aarch64-darwin", macos),
):
    pattern = rf'({re.escape(system)} = \{{\n\s*suffix = "[^"]+";\n\s*hash = ")[^"]+(";)'
    text, count = re.subn(pattern, rf'\g<1>{digest}\g<2>', text, count=1)
    if count != 1:
        raise SystemExit(f"failed to update hash for {system}")

text, count = re.subn(r'clientSrcHash = "[^"]+";', f'clientSrcHash = "{client_src}";', text, count=1)
if count != 1:
    raise SystemExit("failed to update the client source hash")

path.write_text(text)
PY

echo "Updated trusttunnel-client to ${version}"

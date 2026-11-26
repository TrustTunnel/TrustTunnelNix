# Development

This page describes how to build, test, and update the flake.

## Prerequisites

- Nix with flakes enabled.
- A Linux host for the VM tests. The package builds run on all
  supported systems.

## Use the binary cache

Master CI and the update workflow push the packages to the public
Cachix cache `trusttunnel`. To reuse the cache locally, run:

```sh
cachix use trusttunnel
```

The repository secret `CACHIX_AUTH_TOKEN` gives write access. Only
trusted runs on `master` push to the cache. Pull request runs read the
cache and never push.

## Build the packages

```sh
nix build .#trusttunnel-endpoint
nix build .#trusttunnel-client
```

## Run the checks

Run all checks:

```sh
nix flake check --print-build-logs
```

Run one check:

```sh
nix build .#checks.x86_64-linux.endpoint-vm
```

The `config-coverage` check compares the generated configuration keys
with the client source and the endpoint schema. The VM tests boot the
services on Linux. See [Flake outputs](docs/reference/flake-outputs.md)
for the full list of checks.

## Format the Nix files

```sh
nix fmt
```

CI runs `nixfmt --check` on every tracked Nix file.

## Update the packages

The [update-versions](.github/workflows/update-versions.yml) workflow
checks the upstream releases daily at 06:00 UTC and on manual dispatch.
It updates both packages, runs `nix flake check` on `x86_64-linux`, and
commits the package files to `master` when the check passes. CI starts
after the commit. When both packages are current, the run stops after the
version check and does not run `nix flake check`.

The workflow pushes to `master` with the built-in `GITHUB_TOKEN`. The
repository must allow GitHub Actions to push to `master`.

Run the same update locally:

```sh
./scripts/update-versions.sh
nix flake check
```

To preview the changes without writes:

```sh
./scripts/update-versions.sh --dry-run
```

The script updates both packages:

- `trusttunnel-client`: `scripts/update-client.sh` fetches the latest
  release, then updates the version, the platform hashes, and the source
  hash in `pkgs/trusttunnel-client.nix`.
- `trusttunnel-endpoint`: `nix-update --flake --src-only` updates the
  source version and hash in `pkgs/trusttunnel-endpoint.nix`. The script
  passes the version from the version check. The update keeps the
  committed `Cargo.lock` and `boring-v5.patch`. If an upstream release
  breaks them, `nix flake check` fails and the workflow commits nothing.

Update one package directly when needed:

```sh
./scripts/update-client.sh
./scripts/update-client.sh --version 1.2.3
nix run --inputs-from . nixpkgs#nix-update -- \
  --flake --src-only --use-github-releases trusttunnel-endpoint
```

## Project layout

| Path | Content |
| --- | --- |
| `flake.nix` | Flake inputs and outputs. |
| `pkgs/` | Package definitions and patches. |
| `modules/` | NixOS modules for the endpoint and client. |
| `checks/` | Evaluation and configuration coverage checks. |
| `tests/` | NixOS VM tests. |
| `scripts/` | Update helpers. |

The user documentation is in [README.md](README.md) and
[docs/](docs/).

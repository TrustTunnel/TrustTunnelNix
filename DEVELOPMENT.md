# Development

This page describes how to build, test, and update the flake.

## Prerequisites

- Nix with flakes enabled.
- A Linux host for the VM tests. The package builds run on all
  supported systems.

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

The endpoint package uses `nix-update-script`. Update it with your
usual `nix-update` workflow.

The client package uses a helper script:

```sh
./scripts/update-client.sh
./scripts/update-client.sh --version 1.2.3
```

The script fetches the latest release or the requested version, then
updates the version and hashes in `pkgs/trusttunnel-client.nix`.

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

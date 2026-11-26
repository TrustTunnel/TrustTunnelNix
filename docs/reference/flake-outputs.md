# Flake outputs

The flake exposes outputs for four systems: `x86_64-linux`,
`aarch64-linux`, `x86_64-darwin`, and `aarch64-darwin`.

## Packages

- `packages.<system>.default`: the `trusttunnel-endpoint` package.
- `packages.<system>.trusttunnel-endpoint`: the TrustTunnel endpoint.
- `packages.<system>.trusttunnel-client`: the TrustTunnel command-line
  client.

## Overlay

`overlays.default` adds `trusttunnel-endpoint` and `trusttunnel-client`
to a package set.

## NixOS modules

- `nixosModules.default`: imports the endpoint and client modules and
  adds the overlay once.
- `nixosModules.endpoint`: imports the endpoint module and the
  overlay.
- `nixosModules.client`: imports the client module and the overlay.

## Checks

- `checks.<system>.trusttunnel-endpoint`: builds the endpoint.
- `checks.<system>.trusttunnel-client`: builds the client.
- `checks.<system>.config-coverage`: checks that the modules emit
  every configuration key that the client and endpoint expect.
- `checks.<system>.module-eval`: evaluates the NixOS modules.
- `checks.<system>.endpoint-vm`: boots the endpoint in a VM. Linux
  only.
- `checks.<system>.endpoint-socks5-vm`: boots the endpoint with the
  SOCKS5 forward protocol in a VM. Linux only.
- `checks.<system>.client-vm`: boots the endpoint and the client in a
  VM. Linux only.

## Formatter

`formatter.<system>` is `nixfmt`. Run `nix fmt` to format the Nix
files.

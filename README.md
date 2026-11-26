<!-- markdownlint-disable MD041 -->
<p align="center">
<picture>
<source media="(prefers-color-scheme: dark)" srcset="https://cdn.adguardcdn.com/website/github.com/TrustTunnel/logo_dark.svg" width="300px" alt="TrustTunnel" />
<img src="https://cdn.adguardcdn.com/website/github.com/TrustTunnel/logo_light.svg" width="300px" alt="TrustTunnel" />
</picture>
</p>

<p align="center"><a href="https://nixos.org/">Nix</a> packages and <a href="https://nixos.org/">NixOS</a> modules for the TrustTunnel VPN protocol</p>

<p align="center"><a href="#installation">Installation</a>
  · <a href="https://github.com/TrustTunnel/TrustTunnel">Server</a>
  · <a href="https://github.com/TrustTunnel/TrustTunnelClient">CLI client</a>
  · <a href="https://trusttunnel.org">Website</a>
</p>

---

TrustTunnel is a modern, fast, and obfuscated VPN protocol developed by
AdGuard. This flake packages the TrustTunnel endpoint and the
command-line client. It also provides NixOS modules for both services.
Use it to run a TrustTunnel server, a client, or both on NixOS.

## Supported systems

The packages build on these systems:

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin`
- `aarch64-darwin`

The NixOS modules are available on `x86_64-linux` and `aarch64-linux`.

## Installation

### Flake input

Add the flake as an input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    trusttunnel = {
      url = "github:TrustTunnel/TrustTunnelNix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

### Binary cache

The packages are available from a public Cachix cache. The cache covers
all supported systems. Enable the cache once before you build or
install a package.

On systems that do not use NixOS, run:

```sh
cachix use trusttunnel
```

If you do not have the Cachix client, run:

```sh
nix run nixpkgs#cachix -- use trusttunnel
```

On NixOS, add the cache to `configuration.nix`:

```nix
nix.settings = {
  extra-substituters = [ "https://trusttunnel.cachix.org" ];
  extra-trusted-public-keys = [
    "trusttunnel.cachix.org-1:f5OQuI9vTh2G55NYOFLOnOaYtlZPgNIYJn8lr+FW44I="
  ];
};
```

### Build a package

Build a package directly:

```sh
nix build github:TrustTunnel/TrustTunnelNix#trusttunnel-endpoint
nix build github:TrustTunnel/TrustTunnelNix#trusttunnel-client
```

### Install the client

Install the client into a profile:

```sh
nix profile install github:TrustTunnel/TrustTunnelNix#trusttunnel-client
```

## Documentation

- [Run an endpoint](docs/guides/endpoint.md): configure a server with a
  certificate, credentials, and a forward protocol.
- [Run a client](docs/guides/client.md): connect a host through a TUN
  device or a SOCKS5 listener.
- [Handle secrets](docs/guides/secrets.md): keep credentials out of the
  Nix store.
- [Module options](docs/reference/module-options.md): the
  `services.trusttunnel` option reference.
- [Flake outputs](docs/reference/flake-outputs.md): packages, overlays,
  modules, and checks.
- [Packaging notes](docs/explanation/packaging.md): build choices and
  the pinned nixpkgs.
- [Development](DEVELOPMENT.md): build, test, and update the flake.

## License

Apache License 2.0. See [LICENSE](LICENSE).

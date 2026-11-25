# TrustTunnel Nix

Nix packages and NixOS modules for the TrustTunnel VPN endpoint and client.

## Description

This flake packages the TrustTunnel endpoint and the TrustTunnel
command-line client. It also provides NixOS modules for both services.
Use it to run a TrustTunnel server, a client, or both on NixOS.

The endpoint builds from source. The client uses the upstream release
binaries.

## Supported systems

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin`
- `aarch64-darwin`

The NixOS modules are available on the Linux systems. The packages are
available on all four systems.

## Installation

Add the flake as an input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    trusttunnel = {
      url = "github:i-zhirov/trusttunnel-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Build a package directly:

```sh
nix build github:i-zhirov/trusttunnel-nix#trusttunnel-endpoint
nix build github:i-zhirov/trusttunnel-nix#trusttunnel-client
```

Install the client into a profile:

```sh
nix profile install github:i-zhirov/trusttunnel-nix#trusttunnel-client
```

The flake pins `nixos-25.11`. The endpoint uses `boring 4.22.0`, which
matches the boringssl in that release. Set `inputs.nixpkgs.follows` to
keep one nixpkgs in your configuration.

## Endpoint

Import the endpoint module:

```nix
{ config, inputs, ... }:
{
  imports = [ inputs.trusttunnel.nixosModules.endpoint ];

  services.trusttunnel.endpoint = {
    enable = true;
    listenAddress = "0.0.0.0:443";
    openFirewall = true;

    credentialsFile = config.sops.secrets."trusttunnel-credentials".path;

    tls.acme = {
      enable = true;
      email = "admin@vpn.test";
    };
    tls.mainHosts = [ { hostname = "vpn.test"; } ];
  };

  # Port 80 is used for the ACME HTTP-01 challenge.
  networking.firewall.allowedTCPPorts = [ 80 ];
}
```

The credentials file uses this format:

```toml
[[client]]
username = "user1"
password = "secret"
```

The `trusttunnel` user must be able to read the file. A sops secret
with `owner = "trusttunnel"` and `mode = "0400"` works.

For a test endpoint with a self-signed certificate:

```nix
services.trusttunnel.endpoint = {
  enable = true;
  listenAddress = "127.0.0.1:8443";
  credentialsFile = "/run/trusttunnel-credentials.toml";
  tls.selfSigned.enable = true;
  tls.mainHosts = [ { hostname = "vpn.test"; } ];
};
```

The module creates the certificate at service start under
`/var/lib/trusttunnel/certs/<hostname>/`.

## Client

Import the client module:

```nix
{ config, inputs, ... }:
{
  imports = [ inputs.trusttunnel.nixosModules.client ];

  services.trusttunnel.client = {
    enable = true;
    credentialsFile =
      config.sops.secrets."trusttunnel-client-credentials".path;

    endpoint = {
      hostname = "vpn.test";
      addresses = [ "203.0.113.10:443" ];
    };

    listener.tun.enable = true;
    listener.socks = {
      enable = true;
      address = "127.0.0.1:1080";
    };
    killswitch.enable = true;
  };
}
```

The client service runs as root with a restricted capability set. The
credentials file must be readable by root. A sops secret with
`owner = "root"` and `mode = "0400"` works.

Use a deeplink file:

```nix
services.trusttunnel.client = {
  enable = true;
  deeplinkFile = config.sops.secrets."trusttunnel-deeplink".path;
};
```

Use an exported endpoint configuration:

```nix
services.trusttunnel.client = {
  enable = true;
  importConfigFile =
    config.sops.secrets."trusttunnel-endpoint-config".path;
  credentialsFile =
    config.sops.secrets."trusttunnel-client-credentials".path;
};
```

`deeplinkFile` and `importConfigFile` are read at runtime. The module
never writes their contents to the Nix store.

## Both modules

```nix
{ inputs, ... }:
{
  imports = [ inputs.trusttunnel.nixosModules.default ];
}
```

`nixosModules.default` imports the endpoint and client modules and adds
the package overlay once.

## Security

- Use `credentialsFile`. Do not set `credentials` or
  `endpoint.username` and `endpoint.password`. These values are stored
  in the Nix store.
- The endpoint credentials file must be readable by the `trusttunnel`
  user.
- The client credentials file must be readable by root. The service
  runs as root with a restricted capability set.
- Keep secrets in sops or another runtime secret store.

## Module options

The modules define `services.trusttunnel.endpoint` and
`services.trusttunnel.client`. The main options are:

### Endpoint

- `enable`, `package`, `listenAddress`, `openFirewall`
- `credentialsFile`, `credentials`
- `tls.selfSigned`, `tls.acme`, `tls.mainHosts`
- `metrics`, `forwardProtocol`, `timeouts`, `protocols`
- `subscription` (`hostname`, `path`, `address`, `name`, `dnsUpstreams`, `customSni`, `clientRandomPrefix`)
- `settings`, `extraConfig` (freeform `vpn.toml`); `hostsSettings`, `extraHostsConfig` (freeform `hosts.toml`)

### Client

- `enable`, `package`, `credentialsFile`
- `deeplinkFile`, `importConfigFile`
- `endpoint`, `listener.tun`, `listener.socks`
- `killswitch`, `vpnMode`, `exclusions`, `postQuantum`
- `settings`, `extraConfig` (freeform `config.toml`)

Run `nixos-option services.trusttunnel.endpoint` or
`nixos-option services.trusttunnel.client` for the full option
reference.

## Documentation

- [Endpoint module](modules/endpoint.nix)
- [Client module](modules/client.nix)
- [License](LICENSE)

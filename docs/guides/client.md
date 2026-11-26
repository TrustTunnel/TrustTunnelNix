# Run a TrustTunnel client

This guide connects a NixOS host to a TrustTunnel endpoint. The client
sends traffic through a TUN device or a SOCKS5 listener.

## Prerequisites

- NixOS with flakes enabled.
- The flake input from [Installation](../../README.md#installation).
- The endpoint hostname and one or more endpoint addresses.
- A credentials file. See [Handle secrets](secrets.md).

## Configure the client

Add the client module and set the endpoint:

```nix
{ config, inputs, ... }:
{
  imports = [ inputs.trusttunnel.nixosModules.client ];

  services.trusttunnel.client = {
    enable = true;
    credentialsFile =
      config.sops.secrets."trusttunnel-client-credentials".path;

    endpoint = {
      hostname = "vpn.example.com";
      addresses = [ "203.0.113.10:443" ];
    };

    listener.tun.enable = true;
    killswitch.enable = true;
  };
}
```

The client accepts one listener. The TUN listener is the default. To
use a SOCKS5 listener, set `listener.tun.enable = false` and set
`listener.socks.enable = true`.

## Import an endpoint configuration

Instead of separate options, you can import an exported endpoint
configuration. The module reads only the `[endpoint]` section at
runtime:

```nix
services.trusttunnel.client = {
  enable = true;
  importConfigFile =
    config.sops.secrets."trusttunnel-endpoint-config".path;
  credentialsFile =
    config.sops.secrets."trusttunnel-client-credentials".path;
};
```

## Use a deeplink

A deeplink (`tt://`) also configures the endpoint. The module reads the
file at runtime:

```nix
services.trusttunnel.client = {
  enable = true;
  deeplinkFile = config.sops.secrets."trusttunnel-deeplink".path;
};
```

Do not set `deeplinkFile` together with `importConfigFile` or
`credentialsFile`. The setup wizard receives the deeplink as a process
argument. A local user can read the value from `/proc` while the
service starts. Prefer `importConfigFile` and `credentialsFile` for
system services.

## Choose a routing mode

`vpnMode` controls which traffic uses the VPN:

- `general` routes all traffic except the `exclusions` list (default).
- `selective` routes only the `exclusions` list through the VPN.

`killswitch.enable` blocks traffic when the connection is lost. It is
enabled by default.

## Apply the configuration

Apply the configuration with your usual method:

```sh
sudo nixos-rebuild switch --flake .#hostname
```

## Verify the service

Check the service state:

```sh
systemctl status trusttunnel-client
```

Read the logs:

```sh
journalctl -u trusttunnel-client -f
```

## Next steps

- Read the full [module options](../reference/module-options.md).

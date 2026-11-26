# Run a TrustTunnel endpoint

This guide configures a TrustTunnel endpoint on NixOS. The endpoint
accepts VPN connections and forwards traffic to the internet or to a
SOCKS5 proxy.

## Prerequisites

- NixOS with flakes enabled.
- The flake input from [Installation](../../README.md#installation).
- A public hostname for the endpoint.
- A credentials file. See [Handle secrets](secrets.md).

## Configure the endpoint

Add the endpoint module to your NixOS configuration:

```nix
{ config, inputs, ... }:
{
  imports = [ inputs.trusttunnel.nixosModules.endpoint ];

  services.trusttunnel.endpoint = {
    enable = true;
    listenAddress = "0.0.0.0:443";
    openFirewall = true;
    credentialsFile =
      config.sops.secrets."trusttunnel-credentials".path;

    tls.acme = {
      enable = true;
      email = "admin@example.com";
    };
    tls.mainHosts = [ { hostname = "vpn.example.com"; } ];
  };

  # Port 80 is used for the ACME HTTP-01 challenge.
  networking.firewall.allowedTCPPorts = [ 80 ];
}
```

This configuration enables ACME certificates for `vpn.example.com`.
The module opens port 443 for TCP and UDP when `openFirewall` is true.
It generates `vpn.toml` and `hosts.toml` from the options.

## Choose a certificate source

The endpoint needs a certificate for each main host. Choose one source.

### ACME

Use ACME for a public hostname. Set `tls.acme.enable = true` and set
`tls.acme.email`. Open port 80 for the HTTP-01 challenge. The module
uses Let's Encrypt. Set `tls.acme.staging = true` for testing.

### Self-signed certificate

Use a self-signed certificate for a test endpoint. Set
`tls.selfSigned.enable = true`. The module creates the certificate at
service start under `/var/lib/trusttunnel/certs/<hostname>/`. Set
`tls.selfSigned.validityDays` to change the lifetime.

### Your own certificate

Set `tls.mainHosts[].certPath` and `tls.mainHosts[].keyPath` for each
host. Set both or neither. When you set neither, ACME or a self-signed
certificate provides the certificate.

## Provide credentials

The endpoint reads client credentials from `credentialsFile`. The file
uses this TOML format:

```toml
[[client]]
username = "user1"
password = "secret"
```

The `trusttunnel` user must be able to read the file. See
[Handle secrets](secrets.md).

## Choose a forward protocol

Enable exactly one forward protocol:

- Direct is the default: `forwardProtocol.direct.enable = true`.
- For SOCKS5, set `forwardProtocol.direct.enable = false` and set
  `forwardProtocol.socks5.enable = true`. Set
  `forwardProtocol.socks5.address` to the proxy address.

## Optional features

The module also configures:

- Ping and speed test endpoints with `ping` and `speedtest`.
- Prometheus metrics with `metrics`.
- A reverse proxy for non-matching SNI with `tls.reverseProxyHosts` and
  `reverseProxy`.
- Subscription links with `subscription`.

See [Module options](../reference/module-options.md) for all options.

## Apply the configuration

Apply the configuration with your usual method:

```sh
sudo nixos-rebuild switch --flake .#hostname
```

## Verify the service

Check the service state:

```sh
systemctl status trusttunnel-endpoint
```

Read the logs:

```sh
journalctl -u trusttunnel-endpoint -f
```

## Next steps

- Connect a client with [Run a client](client.md).
- Read the full [module options](../reference/module-options.md).

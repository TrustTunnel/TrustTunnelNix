# Handle secrets

The Nix store is readable by all local users. When you set a secret in
a Nix option, the value goes to the store. Use a runtime secret store
and the file options instead.

## Use file options

Set these options to a runtime path:

- `services.trusttunnel.endpoint.credentialsFile`
- `services.trusttunnel.client.credentialsFile`
- `services.trusttunnel.client.importConfigFile`
- `services.trusttunnel.client.deeplinkFile`

The module reads the file at service start and never writes the
contents to the Nix store.

## Avoid inline values

Do not set these options:

- `services.trusttunnel.endpoint.credentials[].password`
- `services.trusttunnel.client.endpoint.username`
- `services.trusttunnel.client.endpoint.password`
- `services.trusttunnel.client.endpoint.clientRandomAuthKey`
- `services.trusttunnel.client.listener.socks.password`

## Create the secret files

The endpoint credentials file uses this TOML format:

```toml
[[client]]
username = "user1"
password = "secret"
```

The client credentials file uses this TOML format:

```toml
username = "user1"
password = "secret"
```

## Set file access

The endpoint service runs as the `trusttunnel` user. The endpoint
credentials file must be readable by that user.

The client service runs as root with a restricted capability set. The
client credentials file must be readable by root.

This `sops-nix` configuration sets the correct owner and mode:

```nix
sops.secrets."trusttunnel-credentials" = {
  owner = "trusttunnel";
  mode = "0400";
};

sops.secrets."trusttunnel-client-credentials" = {
  owner = "root";
  mode = "0400";
};
```

Pass the generated paths to the modules:

```nix
services.trusttunnel.endpoint.credentialsFile =
  config.sops.secrets."trusttunnel-credentials".path;

services.trusttunnel.client.credentialsFile =
  config.sops.secrets."trusttunnel-client-credentials".path;
```

## Protect the deeplink

The client setup wizard receives the deeplink as a process argument. A
local user can read the value from `/proc` while the service starts.
Prefer `importConfigFile` and `credentialsFile` for system services.

## Protect metrics

`services.trusttunnel.endpoint.metrics.perClientMetrics` exposes
usernames and client IPs. Bind the metrics listener to a protected
address.

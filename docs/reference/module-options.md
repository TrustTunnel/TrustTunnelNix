# Module options

This page describes the NixOS options in `services.trusttunnel`. It
lists the types and defaults of the main options.

Run `nixos-option services.trusttunnel.endpoint` or
`nixos-option services.trusttunnel.client` to read the option values on
a running system.

## Endpoint module

### Endpoint core

- `enable` (boolean, default `false`): enable the endpoint service.
- `package` (package, default `pkgs.trusttunnel-endpoint`): package
  that provides the endpoint.
- `listenAddress` (string, default `"0.0.0.0:443"`): address and port
  to listen on.
- `openFirewall` (boolean, default `false`): open the listen port for
  TCP and UDP.
- `ipv6Available` (boolean, default `true`): allow routing of IPv6
  connections.
- `allowPrivateNetwork` (boolean, default `false`): allow connections
  to the private network of the endpoint.
- `rulesFile` (path or null, default `null`): connection filtering
  rules file.
- `defaultMaxHttp2ConnsPerClient` (integer or null, default `null`):
  default maximum HTTP/2 connections per client.
- `defaultMaxHttp3ConnsPerClient` (integer or null, default `null`):
  default maximum HTTP/3 connections per client.

### Endpoint credentials

- `credentials` (list of `{ username, password }`, default `[]`):
  client credentials. The password is stored in the Nix store. Use
  `credentialsFile`.
- `credentialsFile` (path or null, default `null`): TOML file with
  client credentials. The `trusttunnel` user must read the file.

### Endpoint TLS

- `tls.selfSigned.enable` (boolean, default `false`): generate a
  self-signed certificate at service start for hosts without
  `certPath`.
- `tls.selfSigned.validityDays` (integer, default `365`): lifetime of
  the self-signed certificate in days.
- `tls.acme.enable` (boolean, default `false`): request ACME
  certificates from Let's Encrypt.
- `tls.acme.email` (string, default `""`): email for ACME
  registration.
- `tls.acme.staging` (boolean, default `false`): use the Let's Encrypt
  staging server.
- `tls.mainHosts` (list, default `[]`): main TLS hosts for VPN
  traffic. Each entry sets `hostname` and optional `certPath`,
  `keyPath`, and `allowedSni`.
- `tls.pingHosts` (list, default `[]`): hosts for health checks. Each
  entry sets `hostname` and optional `certPath` and `keyPath`.
- `tls.speedtestHosts` (list, default `[]`): hosts for speed tests.
  Each entry sets `hostname` and optional `certPath` and `keyPath`.
- `tls.reverseProxyHosts` (list, default `[]`): hosts proxied to
  `reverseProxy`. Each entry sets `hostname` and optional `certPath`,
  `keyPath`, and `allowedSni`.

### Endpoint forward protocol

- `forwardProtocol.direct.enable` (boolean, default `true`): enable the
  direct forward protocol.
- `forwardProtocol.socks5.enable` (boolean, default `false`): enable
  the SOCKS5 forward protocol.
- `forwardProtocol.socks5.address` (string, default
  `"127.0.0.1:1080"`): SOCKS5 proxy address.
- `forwardProtocol.socks5.extendedAuth` (boolean or null, default
  `null`): enable extended authentication for SOCKS5.

### Endpoint timeouts

Values are in seconds.

| Option | Default |
| --- | --- |
| `timeouts.tlsHandshake` | `10` |
| `timeouts.clientListener` | `600` |
| `timeouts.connectionEstablishment` | `30` |
| `timeouts.tcpConnection` | `604800` |
| `timeouts.udpConnection` | `300` |

### Endpoint protocols

Values are in bytes unless the option name says otherwise.

| Option | Default |
| --- | --- |
| `protocols.http1.uploadBufferSize` | `32768` |
| `protocols.http2.initialConnectionWindowSize` | `8388608` |
| `protocols.http2.initialStreamWindowSize` | `131072` |
| `protocols.http2.maxConcurrentStreams` | `1000` |
| `protocols.http2.maxFrameSize` | `16384` |
| `protocols.http2.headerTableSize` | `65536` |
| `protocols.quic.recvUdpPayloadSize` | `1350` |
| `protocols.quic.sendUdpPayloadSize` | `1350` |
| `protocols.quic.initialMaxData` | `104857600` |
| `protocols.quic.initialMaxStreamDataBidiLocal` | `1048576` |
| `protocols.quic.initialMaxStreamDataBidiRemote` | `1048576` |
| `protocols.quic.initialMaxStreamDataUni` | `1048576` |
| `protocols.quic.initialMaxStreamsBidi` | `4096` |
| `protocols.quic.initialMaxStreamsUni` | `4096` |
| `protocols.quic.maxConnectionWindow` | `25165824` |
| `protocols.quic.maxStreamWindow` | `16777216` |
| `protocols.quic.disableActiveMigration` | `true` |
| `protocols.quic.enableEarlyData` | `true` |
| `protocols.quic.messageQueueCapacity` | `4096` |

### Endpoint ping and speed test

- `ping.enable` (boolean, default `false`): enable ping support.
- `ping.path` (string or null, default `null`): ping path.
- `speedtest.enable` (boolean, default `false`): enable speed test
  support.
- `speedtest.path` (string or null, default `null`): speed test path.

### Endpoint metrics

- `metrics.enable` (boolean, default `false`): enable Prometheus
  metrics.
- `metrics.address` (string, default `"127.0.0.1:1987"`): metrics
  listener address.
- `metrics.requestTimeout` (integer, default `3`): metrics request
  timeout in seconds.
- `metrics.perClientMetrics` (boolean, default `false`): expose
  per-user series and the `/clients` endpoint. This exposes usernames
  and client IPs.

### Endpoint ICMP

- `icmp.enable` (boolean, default `false`): enable ICMP tunneling.
- `icmp.interfaceName` (string, default `"eth0"`): interface for ICMP.
- `icmp.requestTimeout` (integer, default `3`): ICMP request timeout in
  seconds.
- `icmp.recvMessageQueueCapacity` (integer, default `256`): ICMP
  receive queue capacity.

### Endpoint reverse proxy

- `reverseProxy.enable` (boolean, default `false`): enable the default
  reverse proxy for non-matching SNI.
- `reverseProxy.serverAddress` (string, default `"127.0.0.1:80"`):
  backend address.
- `reverseProxy.pathMask` (string, default `"/"`): path mask. It must
  start with a slash.
- `reverseProxy.h3BackwardCompatibility` (boolean or null, default
  `null`): enable HTTP/3 backward compatibility.

### Endpoint authentication

- `auth.failureStatusCode` (integer or null, default `null`): HTTP
  status code for authentication failure of CONNECT requests.
- `auth.nonConnectFailureStatusCode` (integer or null, default
  `null`): HTTP status code for authentication failure of non-CONNECT
  requests. Null uses `auth.failureStatusCode`.

### Endpoint subscription

- `subscription.enable` (boolean, default `false`): enable
  subscription link generation.
- `subscription.hostname` (string, default `""`): public hostname in
  subscription links.
- `subscription.path` (string, default `"/subscription"`): URL path
  for the subscription endpoint.
- `subscription.address` (string, default `""`): subscription server
  address.
- `subscription.name` (string, default `""`): display name.
- `subscription.dnsUpstreams` (list of strings, default `[]`): DNS
  upstreams for subscription clients.
- `subscription.customSni` (string or null, default `null`): custom
  SNI for subscription clients.
- `subscription.clientRandomPrefix` (string or null, default `null`):
  client random prefix or prefix and mask in hex.

### Endpoint freeform configuration

- `settings` (attribute set, default `{}`): extra `vpn.toml` keys
  rendered as TOML.
- `extraConfig` (lines, default `""`): raw TOML appended to
  `vpn.toml`.
- `hostsSettings` (attribute set, default `{}`): extra `hosts.toml`
  keys rendered as TOML.
- `extraHostsConfig` (lines, default `""`): raw TOML appended to
  `hosts.toml`.

## Client module

### Client core

- `enable` (boolean, default `false`): enable the client service.
- `package` (package, default `pkgs.trusttunnel-client`): package that
  provides the client.
- `deeplinkFile` (path or null, default `null`): file with a `tt://`
  deeplink. The module reads the file at runtime.
- `importConfigFile` (path or null, default `null`): exported endpoint
  configuration. The module reads the `[endpoint]` section at runtime.
- `credentialsFile` (path or null, default `null`): TOML file with a
  username and password. The module reads the file at runtime.
- `logLevel` (`info`, `debug`, or `trace`, default `info`): logging
  level.
- `vpnMode` (`general` or `selective`, default `general`): routing
  policy.
- `exclusions` (list of strings, default `[]`): domains and IPs for the
  routing policy.
- `exclusionsTcpEarlyAck` (boolean, default `false`): read the TLS SNI
  through a fake upstream for connections to scannable ports.
- `exclusionsPreresolve` (boolean, default `true`): pre-resolve
  DNS-resolvable exclusions in the background.
- `exclusionsPreresolveMaxQueries` (integer, default `50`): maximum
  exclusion domains to pre-resolve per cycle.
- `exclusionsScannablePorts` (string, default
  `"443,80,8080,8008,853"`): ports for domain extraction and exclusion
  matching. Supports ranges.
- `postQuantum` (boolean, default `true`): enable post-quantum key
  exchange.

### Client killswitch

- `killswitch.enable` (boolean, default `true`): block traffic when the
  VPN connection is lost.
- `killswitch.allowPorts` (list of integers, default `[]`): local
  ports to allow while the killswitch is active.

### Client endpoint

- `endpoint.hostname` (string, default `""`): endpoint hostname for
  TLS.
- `endpoint.addresses` (list of strings, default `[]`): endpoint
  addresses as `IP:port` or `hostname:port`.
- `endpoint.username` (string, default `""`): authentication username.
  Use `credentialsFile`.
- `endpoint.password` (string, default `""`): authentication password.
  Use `credentialsFile`.
- `endpoint.ipv6` (boolean, default `true`): allow routing of IPv6
  traffic.
- `endpoint.clientRandom` (string, default `""`): TLS client random
  prefix or mask in hex.
- `endpoint.clientRandomAuthKey` (string, default `""`): TLS client
  random authentication key in hex. Use `credentialsFile`.
- `endpoint.skipVerification` (boolean, default `false`): skip
  endpoint certificate verification.
- `endpoint.certificate` (path or null, default `null`): endpoint
  certificate in PEM format.
- `endpoint.customSni` (string or null, default `null`): custom SNI for
  the TLS handshake.
- `endpoint.protocol` (`http2` or `http3`, default `http2`): upstream
  protocol.
- `endpoint.tlsProfile` (`chrome`, `chrome_canary`, `safari`,
  `firefox`, `okhttp`, `openssl`, or `boringssl`, default `chrome`):
  TLS ClientHello fingerprint to mimic.
- `endpoint.antiDpi` (boolean, default `false`): enable anti-DPI
  measures.
- `endpoint.dnsUpstreams` (list of strings, default `[]`): DNS
  resolvers for queries through the VPN. An empty list uses AdGuard
  DNS.

### Client TUN listener

- `listener.tun.enable` (boolean, default `true`): enable the TUN
  device listener.
- `listener.tun.interface` (string, default `""`): network interface
  for the VPN. The client detects it when the value is empty.
- `listener.tun.deviceName` (string, default `""`): TUN device name.
  The kernel assigns one when the value is empty.
- `listener.tun.useExisting` (boolean, default `false`): attach to the
  device named by `deviceName`. Requires `deviceName`.
- `listener.tun.includedRoutes` (list of strings, default
  `["0.0.0.0/0", "2000::/3"]`): routes on the virtual interface.
- `listener.tun.excludedRoutes` (list of strings, default private and
  local ranges): routes excluded from the VPN.
- `listener.tun.mtu` (integer, default `1280`): MTU on the virtual
  interface.
- `listener.tun.tcpRecvBufferSize` (integer, default `0`): TCP receive
  window size in bytes. `0` uses the optimized default.
- `listener.tun.tcpSendBufferSize` (integer, default `0`): TCP send
  buffer size in bytes. `0` uses the optimized default.
- `listener.tun.changeSystemDns` (boolean, default `true`): allow the
  client to change system DNS servers.

### Client SOCKS5 listener

- `listener.socks.enable` (boolean, default `false`): enable the
  SOCKS5 proxy listener.
- `listener.socks.address` (string, default `"127.0.0.1:1080"`):
  SOCKS5 proxy address.
- `listener.socks.username` (string or null, default `null`): username
  for SOCKS authentication.
- `listener.socks.password` (string or null, default `null`): password
  for SOCKS authentication. Use a runtime secret store.

### Client freeform configuration

- `settings` (attribute set, default `{}`): extra `config.toml` keys
  rendered as TOML.
- `extraConfig` (lines, default `""`): raw TOML appended to
  `config.toml`.

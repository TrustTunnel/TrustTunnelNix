{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.trusttunnel.endpoint;

  listenPort =
    let
      last = lib.last (lib.splitString ":" cfg.listenAddress);
    in
    if builtins.match "[0-9]+" last != null then lib.toInt last else null;

  selfSignedCertDir = hostname: "/var/lib/trusttunnel/certs/${hostname}";

  selfSignedHosts = lib.filter (host: host.certPath == null) (
    cfg.tls.mainHosts ++ cfg.tls.pingHosts ++ cfg.tls.speedtestHosts ++ cfg.tls.reverseProxyHosts
  );

  useSelfSigned = cfg.tls.selfSigned.enable && !cfg.tls.acme.enable;

  processHost =
    host:
    let
      useACME = cfg.tls.acme.enable && host.certPath == null;
      useSelfSignedForHost = useSelfSigned && host.certPath == null;
    in
    {
      inherit (host) hostname;
      certPath =
        if useACME then
          "/var/lib/acme/${host.hostname}/fullchain.pem"
        else if useSelfSignedForHost then
          "${selfSignedCertDir host.hostname}/cert.pem"
        else
          host.certPath;
      keyPath =
        if useACME then
          "/var/lib/acme/${host.hostname}/key.pem"
        else if useSelfSignedForHost then
          "${selfSignedCertDir host.hostname}/key.pem"
        else
          host.keyPath;
    };

  processedMainHosts = map (h: (processHost h) // { inherit (h) allowedSni; }) cfg.tls.mainHosts;
  processedPingHosts = map processHost cfg.tls.pingHosts;
  processedSpeedtestHosts = map processHost cfg.tls.speedtestHosts;
  processedReverseProxyHosts = map (
    h:
    (processHost h)
    // {
      inherit (h)
        allowedSni
        serverAddress
        pathMask
        h3BackwardCompatibility
        ;
    }
  ) cfg.tls.reverseProxyHosts;

  credentialsFile =
    if cfg.credentialsFile != null then
      cfg.credentialsFile
    else
      pkgs.writeText "credentials.toml" ''
        ${lib.concatStringsSep "\n" (
          map (c: ''
            [[client]]
            username = "${c.username}"
            password = "${if c.password == null then "" else c.password}"
          '') cfg.credentials
        )}
      '';

  vpnToml = pkgs.writeText "vpn.toml" ''
    listen_address = "${cfg.listenAddress}"
    ipv6_available = ${lib.boolToString cfg.ipv6Available}
    allow_private_network_connections = ${lib.boolToString cfg.allowPrivateNetwork}
    tls_handshake_timeout_secs = ${toString cfg.timeouts.tlsHandshake}
    client_listener_timeout_secs = ${toString cfg.timeouts.clientListener}
    connection_establishment_timeout_secs = ${toString cfg.timeouts.connectionEstablishment}
    tcp_connections_timeout_secs = ${toString cfg.timeouts.tcpConnection}
    udp_connections_timeout_secs = ${toString cfg.timeouts.udpConnection}
    credentials_file = "${credentialsFile}"
    ${lib.optionalString (cfg.rulesFile != null) ''rules_file = "${cfg.rulesFile}"''}
    ${lib.optionalString cfg.speedtest.enable "speedtest_enable = true"}
    ${lib.optionalString cfg.ping.enable "ping_enable = true"}
    ${lib.optionalString (cfg.ping.path != null) ''ping_path = "${cfg.ping.path}"''}
    ${lib.optionalString (cfg.speedtest.path != null) ''speedtest_path = "${cfg.speedtest.path}"''}
    ${lib.optionalString (
      cfg.auth.failureStatusCode != null
    ) "auth_failure_status_code = ${toString cfg.auth.failureStatusCode}"}
    ${lib.optionalString (
      cfg.defaultMaxHttp2ConnsPerClient != null
    ) "default_max_http2_conns_per_client = ${toString cfg.defaultMaxHttp2ConnsPerClient}"}
    ${lib.optionalString (
      cfg.defaultMaxHttp3ConnsPerClient != null
    ) "default_max_http3_conns_per_client = ${toString cfg.defaultMaxHttp3ConnsPerClient}"}

    [listen_protocols.http1]
    upload_buffer_size = ${toString cfg.protocols.http1.uploadBufferSize}

    [listen_protocols.http2]
    initial_connection_window_size = ${toString cfg.protocols.http2.initialConnectionWindowSize}
    initial_stream_window_size = ${toString cfg.protocols.http2.initialStreamWindowSize}
    max_concurrent_streams = ${toString cfg.protocols.http2.maxConcurrentStreams}
    max_frame_size = ${toString cfg.protocols.http2.maxFrameSize}
    header_table_size = ${toString cfg.protocols.http2.headerTableSize}

    [listen_protocols.quic]
    recv_udp_payload_size = ${toString cfg.protocols.quic.recvUdpPayloadSize}
    send_udp_payload_size = ${toString cfg.protocols.quic.sendUdpPayloadSize}
    initial_max_data = ${toString cfg.protocols.quic.initialMaxData}
    initial_max_stream_data_bidi_local = ${toString cfg.protocols.quic.initialMaxStreamDataBidiLocal}
    initial_max_stream_data_bidi_remote = ${toString cfg.protocols.quic.initialMaxStreamDataBidiRemote}
    initial_max_stream_data_uni = ${toString cfg.protocols.quic.initialMaxStreamDataUni}
    initial_max_streams_bidi = ${toString cfg.protocols.quic.initialMaxStreamsBidi}
    initial_max_streams_uni = ${toString cfg.protocols.quic.initialMaxStreamsUni}
    max_connection_window = ${toString cfg.protocols.quic.maxConnectionWindow}
    max_stream_window = ${toString cfg.protocols.quic.maxStreamWindow}
    disable_active_migration = ${lib.boolToString cfg.protocols.quic.disableActiveMigration}
    enable_early_data = ${lib.boolToString cfg.protocols.quic.enableEarlyData}
    message_queue_capacity = ${toString cfg.protocols.quic.messageQueueCapacity}

    ${lib.optionalString cfg.reverseProxy.enable ''
      [reverse_proxy]
      server_address = "${cfg.reverseProxy.serverAddress}"
      ${lib.optionalString (
        cfg.reverseProxy.pathMask != null
      ) ''path_mask = "${cfg.reverseProxy.pathMask}"''}
      ${lib.optionalString (
        cfg.reverseProxy.h3BackwardCompatibility != null
      ) "h3_backward_compatibility = ${lib.boolToString cfg.reverseProxy.h3BackwardCompatibility}"}
    ''}

    ${lib.optionalString cfg.metrics.enable ''
      [metrics]
      address = "${cfg.metrics.address}"
      request_timeout_secs = ${toString cfg.metrics.requestTimeout}
      ${lib.optionalString cfg.metrics.perClientMetrics "per_client_metrics = ${lib.boolToString cfg.metrics.perClientMetrics}"}
    ''}

    ${lib.optionalString cfg.icmp.enable ''
      [icmp]
      interface_name = "${cfg.icmp.interfaceName}"
      request_timeout_secs = ${toString cfg.icmp.requestTimeout}
      recv_message_queue_capacity = ${toString cfg.icmp.recvMessageQueueCapacity}
    ''}

    [forward_protocol]
    ${lib.optionalString cfg.forwardProtocol.direct.enable "direct = {}"}
    ${lib.optionalString cfg.forwardProtocol.socks5.enable ''
      [forward_protocol.socks5]
      address = "${cfg.forwardProtocol.socks5.address}"
      ${lib.optionalString (
        cfg.forwardProtocol.socks5.extendedAuth != null
      ) "extended_auth = ${lib.boolToString cfg.forwardProtocol.socks5.extendedAuth}"}
    ''}
  '';

  hostsToml = pkgs.writeText "hosts.toml" ''
    ${lib.concatStringsSep "\n" (
      map (h: ''
        [[main_hosts]]
        hostname = "${h.hostname}"
        cert_chain_path = "${h.certPath}"
        private_key_path = "${h.keyPath}"
        ${lib.optionalString (h.allowedSni != null)
          "allowed_sni = [${lib.concatStringsSep ", " (map (s: "\"${s}\"") h.allowedSni)}]"
        }
      '') processedMainHosts
    )}

    ${lib.concatStringsSep "\n" (
      map (h: ''
        [[ping_hosts]]
        hostname = "${h.hostname}"
        cert_chain_path = "${h.certPath}"
        private_key_path = "${h.keyPath}"
      '') processedPingHosts
    )}

    ${lib.concatStringsSep "\n" (
      map (h: ''
        [[speedtest_hosts]]
        hostname = "${h.hostname}"
        cert_chain_path = "${h.certPath}"
        private_key_path = "${h.keyPath}"
      '') processedSpeedtestHosts
    )}

    ${lib.concatStringsSep "\n" (
      map (h: ''
        [[reverse_proxy_hosts]]
        hostname = "${h.hostname}"
        cert_chain_path = "${h.certPath}"
        private_key_path = "${h.keyPath}"
        ${lib.optionalString (h.allowedSni != null)
          "allowed_sni = [${lib.concatStringsSep ", " (map (s: "\"${s}\"") h.allowedSni)}]"
        }
        server_address = "${h.serverAddress}"
        ${lib.optionalString (h.pathMask != null) ''path_mask = "${h.pathMask}"''}
        ${lib.optionalString (
          h.h3BackwardCompatibility != null
        ) "h3_backward_compatibility = ${lib.boolToString h.h3BackwardCompatibility}"}
      '') processedReverseProxyHosts
    )}
  '';

  acmeHosts = builtins.filter (host: host.certPath == null) (
    cfg.tls.mainHosts ++ cfg.tls.reverseProxyHosts
  );

  selfSignedScript = ''
    ${lib.concatStringsSep "\n" (
      map (host: ''
        cert_dir="${selfSignedCertDir host.hostname}"
        ${pkgs.coreutils}/bin/mkdir -p "$cert_dir"
        if [ ! -s "$cert_dir/cert.pem" ] || [ ! -s "$cert_dir/key.pem" ]; then
          ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 \
            -keyout "$cert_dir/key.pem" -out "$cert_dir/cert.pem" \
            -days ${toString cfg.tls.selfSigned.validityDays} -nodes \
            -subj "/CN=${host.hostname}" \
            -addext "subjectAltName=DNS:${host.hostname}"
          ${pkgs.coreutils}/bin/chmod 600 "$cert_dir/key.pem"
          ${pkgs.coreutils}/bin/chmod 644 "$cert_dir/cert.pem"
        fi
      '') selfSignedHosts
    )}
  '';
in
{
  meta = {
    maintainers = [
      {
        name = "Ilya Zhirov";
        github = "i-zhirov";
      }
    ];
    doc = "https://github.com/i-zhirov/trusttunnel-nix/blob/main/README.md#module-options";
  };

  options.services.trusttunnel.endpoint = {
    enable = lib.mkEnableOption "TrustTunnel VPN endpoint server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.trusttunnel-endpoint;
      defaultText = lib.literalExpression "pkgs.trusttunnel-endpoint";
      description = "TrustTunnel endpoint package to use.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0:443";
      description = "Address and port to listen on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the configured port in the firewall for TCP and UDP.";
    };

    ipv6Available = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether IPv6 connections can be routed.";
    };

    allowPrivateNetwork = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow connections to the endpoint's private network.";
    };

    credentials = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            username = lib.mkOption {
              type = lib.types.str;
              description = "Client username.";
            };
            password = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Client password. Prefer credentialsFile to keep secrets out of the Nix store.";
            };
          };
        }
      );
      default = [ ];
      example = [
        {
          username = "user1";
          password = "secret";
        }
      ];
      description = "Client credentials. Values are stored in the Nix store. Prefer credentialsFile.";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a TOML credentials file. This is the supported secret path. The file must be readable by the trusttunnel user.";
    };

    rulesFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a connection filtering rules file.";
    };

    tls = {
      selfSigned = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate self-signed certificates at service start for hosts without certPath.";
        };

        validityDays = lib.mkOption {
          type = lib.types.int;
          default = 365;
          description = "Self-signed certificate validity in days.";
        };
      };

      acme = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable automatic ACME certificate generation via Let's Encrypt.";
        };

        email = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Email for ACME registration.";
        };

        staging = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Use the Let's Encrypt staging server.";
        };
      };

      mainHosts = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              hostname = lib.mkOption {
                type = lib.types.str;
                description = "Hostname for VPN traffic.";
              };
              certPath = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Path to the certificate. Null uses ACME or a self-signed certificate.";
              };
              keyPath = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Path to the private key. Null uses ACME or a self-signed certificate.";
              };
              allowedSni = lib.mkOption {
                type = lib.types.nullOr (lib.types.listOf lib.types.str);
                default = null;
                example = [
                  "ru.hexbrains.com"
                  "alt.hexbrains.com"
                ];
                description = "Additional SNI hostnames that clients can send.";
              };
            };
          }
        );
        default = [ ];
        example = [
          {
            hostname = "vpn.example.com";
            certPath = /path/to/cert.pem;
            keyPath = /path/to/key.pem;
          }
        ];
        description = "Main TLS hosts for VPN traffic.";
      };

      pingHosts = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              hostname = lib.mkOption {
                type = lib.types.str;
                description = "Hostname for health checks.";
              };
              certPath = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Path to the certificate.";
              };
              keyPath = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Path to the private key.";
              };
            };
          }
        );
        default = [ ];
        description = "Ping hosts for health checks.";
      };

      speedtestHosts = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              hostname = lib.mkOption {
                type = lib.types.str;
                description = "Hostname for speed tests.";
              };
              certPath = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Path to the certificate.";
              };
              keyPath = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Path to the private key.";
              };
            };
          }
        );
        default = [ ];
        description = "Speedtest hosts.";
      };

      reverseProxyHosts = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              hostname = lib.mkOption {
                type = lib.types.str;
                description = "Hostname for this reverse proxy host. It must match the SNI.";
              };
              certPath = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Path to the TLS certificate chain.";
              };
              keyPath = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Path to the TLS private key.";
              };
              allowedSni = lib.mkOption {
                type = lib.types.nullOr (lib.types.listOf lib.types.str);
                default = null;
                example = [
                  "ru.hexbrains.com"
                  "alt.hexbrains.com"
                ];
                description = "Allowed SNI override for client connections.";
              };
              serverAddress = lib.mkOption {
                type = lib.types.str;
                description = "Backend server address, for example 127.0.0.1:80.";
              };
              pathMask = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Path mask for reverse proxy routing.";
              };
              h3BackwardCompatibility = lib.mkOption {
                type = lib.types.nullOr lib.types.bool;
                default = null;
                description = "Enable HTTP/3 backward compatibility for this host.";
              };
            };
          }
        );
        default = [ ];
        example = [
          {
            hostname = "example.com";
            serverAddress = "127.0.0.1:80";
          }
        ];
        description = "TLS connections that match these hostnames are proxied to a backend server.";
      };
    };

    timeouts = {
      tlsHandshake = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "TLS handshake timeout in seconds.";
      };
      clientListener = lib.mkOption {
        type = lib.types.int;
        default = 600;
        description = "Client listener timeout in seconds.";
      };
      connectionEstablishment = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Connection establishment timeout in seconds.";
      };
      tcpConnection = lib.mkOption {
        type = lib.types.int;
        default = 604800;
        description = "TCP connection timeout in seconds.";
      };
      udpConnection = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "UDP connection timeout in seconds.";
      };
    };

    protocols = {
      http1 = {
        uploadBufferSize = lib.mkOption {
          type = lib.types.int;
          default = 32768;
          description = "HTTP/1 upload buffer size in bytes.";
        };
      };
      http2 = {
        initialConnectionWindowSize = lib.mkOption {
          type = lib.types.int;
          default = 8388608;
          description = "HTTP/2 initial connection window size in bytes.";
        };
        initialStreamWindowSize = lib.mkOption {
          type = lib.types.int;
          default = 131072;
          description = "HTTP/2 initial stream window size in bytes.";
        };
        maxConcurrentStreams = lib.mkOption {
          type = lib.types.int;
          default = 1000;
          description = "HTTP/2 maximum concurrent streams.";
        };
        maxFrameSize = lib.mkOption {
          type = lib.types.int;
          default = 16384;
          description = "HTTP/2 maximum frame size in bytes.";
        };
        headerTableSize = lib.mkOption {
          type = lib.types.int;
          default = 65536;
          description = "HTTP/2 header table size in bytes.";
        };
      };
      quic = {
        recvUdpPayloadSize = lib.mkOption {
          type = lib.types.int;
          default = 1350;
          description = "QUIC receive UDP payload size in bytes.";
        };
        sendUdpPayloadSize = lib.mkOption {
          type = lib.types.int;
          default = 1350;
          description = "QUIC send UDP payload size in bytes.";
        };
        initialMaxData = lib.mkOption {
          type = lib.types.int;
          default = 104857600;
          description = "QUIC initial maximum data.";
        };
        initialMaxStreamDataBidiLocal = lib.mkOption {
          type = lib.types.int;
          default = 1048576;
          description = "QUIC initial maximum local bidirectional stream data.";
        };
        initialMaxStreamDataBidiRemote = lib.mkOption {
          type = lib.types.int;
          default = 1048576;
          description = "QUIC initial maximum remote bidirectional stream data.";
        };
        initialMaxStreamDataUni = lib.mkOption {
          type = lib.types.int;
          default = 1048576;
          description = "QUIC initial maximum unidirectional stream data.";
        };
        initialMaxStreamsBidi = lib.mkOption {
          type = lib.types.int;
          default = 4096;
          description = "QUIC initial maximum bidirectional streams.";
        };
        initialMaxStreamsUni = lib.mkOption {
          type = lib.types.int;
          default = 4096;
          description = "QUIC initial maximum unidirectional streams.";
        };
        maxConnectionWindow = lib.mkOption {
          type = lib.types.int;
          default = 25165824;
          description = "QUIC maximum connection window.";
        };
        maxStreamWindow = lib.mkOption {
          type = lib.types.int;
          default = 16777216;
          description = "QUIC maximum stream window.";
        };
        disableActiveMigration = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Disable QUIC active migration.";
        };
        enableEarlyData = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable QUIC early data.";
        };
        messageQueueCapacity = lib.mkOption {
          type = lib.types.int;
          default = 4096;
          description = "QUIC message queue capacity.";
        };
      };
    };

    ping = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable ping support.";
      };
      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Ping path.";
      };
    };

    speedtest = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable speedtest support.";
      };
      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Speedtest path.";
      };
    };

    metrics = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Prometheus metrics.";
      };
      address = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1:1987";
        description = "Metrics listener address.";
      };
      requestTimeout = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Metrics request timeout in seconds.";
      };
      perClientMetrics = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Expose per-user metric series and the /clients JSON endpoint. It exposes usernames and client IPs, so use a protected listener.";
      };
    };

    icmp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable ICMP tunneling.";
      };
      interfaceName = lib.mkOption {
        type = lib.types.str;
        default = "eth0";
        description = "Interface name for ICMP.";
      };
      requestTimeout = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "ICMP request timeout in seconds.";
      };
      recvMessageQueueCapacity = lib.mkOption {
        type = lib.types.int;
        default = 256;
        description = "ICMP receive message queue capacity.";
      };
    };

    reverseProxy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the default reverse proxy for non-matching SNI.";
      };
      serverAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1:80";
        description = "Default reverse proxy backend address.";
      };
      pathMask = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path mask for the default reverse proxy.";
      };
      h3BackwardCompatibility = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Enable HTTP/3 backward compatibility for the default reverse proxy.";
      };
    };

    auth = {
      failureStatusCode = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "HTTP status code to return on authentication failure.";
      };
    };

    defaultMaxHttp2ConnsPerClient = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Default maximum HTTP/2 connections per client.";
    };

    defaultMaxHttp3ConnsPerClient = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Default maximum HTTP/3 connections per client.";
    };

    forwardProtocol = {
      direct = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable the direct forward protocol.";
        };
      };
      socks5 = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable the SOCKS5 forward protocol.";
        };
        address = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1:1080";
          description = "SOCKS5 proxy address.";
        };
        extendedAuth = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Enable extended authentication for SOCKS5.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.credentialsFile != null || lib.all (c: c.password != null) cfg.credentials;
        message = "services.trusttunnel.endpoint.credentials: set a password or use credentialsFile.";
      }
    ];

    warnings =
      lib.optional (cfg.credentials != [ ])
        "services.trusttunnel.endpoint.credentials stores passwords in the Nix store. Use credentialsFile instead.";

    users.groups.trusttunnel = { };
    users.users.trusttunnel = {
      isSystemUser = true;
      group = "trusttunnel";
      extraGroups = lib.optional cfg.tls.acme.enable "acme";
      description = "TrustTunnel VPN Endpoint service user";
    };

    security.acme = lib.mkIf cfg.tls.acme.enable {
      acceptTerms = true;
      defaults.email = cfg.tls.acme.email;
      defaults.server =
        if cfg.tls.acme.staging then
          "https://acme-staging-v02.api.letsencrypt.org/directory"
        else
          "https://acme-v02.api.letsencrypt.org/directory";

      certs = builtins.listToAttrs (
        map (host: {
          name = host.hostname;
          value = { };
        }) acmeHosts
      );
    };

    systemd.services.trusttunnel-endpoint = {
      description = "TrustTunnel VPN Endpoint";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
      ]
      ++ lib.optionals cfg.tls.acme.enable (map (host: "acme-${host.hostname}.service") acmeHosts);
      wants = lib.optionals cfg.tls.acme.enable (map (host: "acme-${host.hostname}.service") acmeHosts);

      preStart = lib.optionalString useSelfSigned selfSignedScript;

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/trusttunnel_endpoint ${vpnToml} ${hostsToml}";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = "5s";

        User = "trusttunnel";
        Group = "trusttunnel";
        NoNewPrivileges = true;

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;

        StateDirectory = lib.optional useSelfSigned "trusttunnel";
        StateDirectoryMode = "0700";
        ReadWritePaths = lib.optionals cfg.tls.acme.enable [ "/var/lib/acme" ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.optionals (cfg.openFirewall && listenPort != null) [
      listenPort
    ];
    networking.firewall.allowedUDPPorts = lib.optionals (cfg.openFirewall && listenPort != null) [
      listenPort
    ];
  };
}

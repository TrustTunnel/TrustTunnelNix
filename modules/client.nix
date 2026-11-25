{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.trusttunnel.client;

  formats = pkgs.formats.toml { };

  runtimeConfig = "/run/trusttunnel-client/config.toml";

  hasRuntimeSource =
    cfg.deeplinkFile != null || cfg.importConfigFile != null || cfg.credentialsFile != null;

  tunListenerConfig = lib.optionalString cfg.listener.tun.enable ''

    [listener.tun]
    bound_if = "${cfg.listener.tun.interface}"
    device_name = "${cfg.listener.tun.deviceName}"
    use_existing = ${lib.boolToString cfg.listener.tun.useExisting}
    included_routes = [${
      lib.concatStringsSep ", " (map (r: "\"${r}\"") cfg.listener.tun.includedRoutes)
    }]
    excluded_routes = [${
      lib.concatStringsSep ", " (map (r: "\"${r}\"") cfg.listener.tun.excludedRoutes)
    }]
    mtu_size = ${toString cfg.listener.tun.mtu}
    tcp_recv_buf_size = ${toString cfg.listener.tun.tcpRecvBufferSize}
    tcp_send_buf_size = ${toString cfg.listener.tun.tcpSendBufferSize}
    change_system_dns = ${lib.boolToString cfg.listener.tun.changeSystemDns}
  '';

  socksListenerConfig = lib.optionalString cfg.listener.socks.enable ''

    [listener.socks]
    address = "${cfg.listener.socks.address}"
    ${lib.optionalString (
      cfg.listener.socks.username != null
    ) ''username = "${cfg.listener.socks.username}"''}
    ${lib.optionalString (
      cfg.listener.socks.password != null
    ) ''password = "${cfg.listener.socks.password}"''}
  '';

  baseConfig = ''
    loglevel = "${cfg.logLevel}"
    vpn_mode = "${cfg.vpnMode}"
    killswitch_enabled = ${lib.boolToString cfg.killswitch.enable}
    killswitch_allow_ports = [${lib.concatStringsSep ", " (map toString cfg.killswitch.allowPorts)}]
    post_quantum_group_enabled = ${lib.boolToString cfg.postQuantum}
    exclusions_tcp_early_ack_enabled = ${lib.boolToString cfg.exclusionsTcpEarlyAck}
    exclusions_preresolve_enabled = ${lib.boolToString cfg.exclusionsPreresolve}
    exclusions_preresolve_max_queries = ${toString cfg.exclusionsPreresolveMaxQueries}
    exclusions_scannable_ports = "${cfg.exclusionsScannablePorts}"
    exclusions = [${lib.concatStringsSep ", " (map (e: "\"${e}\"") cfg.exclusions)}]

    ${lib.optionalString (cfg.settings != { }) (
      builtins.readFile (formats.generate "client-extra.toml" cfg.settings)
    )}
    ${cfg.extraConfig}
  '';

  directEndpointConfig = ''
    [endpoint]
    hostname = "${cfg.endpoint.hostname}"
    addresses = [${lib.concatStringsSep ", " (map (a: "\"${a}\"") cfg.endpoint.addresses)}]
    has_ipv6 = ${lib.boolToString cfg.endpoint.ipv6}
    username = "${cfg.endpoint.username}"
    password = "${cfg.endpoint.password}"
    client_random = "${cfg.endpoint.clientRandom}"
    client_random_auth_key = "${cfg.endpoint.clientRandomAuthKey}"
    skip_verification = ${lib.boolToString cfg.endpoint.skipVerification}
    ${lib.optionalString (
      cfg.endpoint.certificate != null
    ) ''certificate = "${cfg.endpoint.certificate}"''}
    ${lib.optionalString (cfg.endpoint.customSni != null) ''custom_sni = "${cfg.endpoint.customSni}"''}
    upstream_protocol = "${cfg.endpoint.protocol}"
    tls_profile = "${cfg.endpoint.tlsProfile}"
    anti_dpi = ${lib.boolToString cfg.endpoint.antiDpi}
    dns_upstreams = [${lib.concatStringsSep ", " (map (d: "\"${d}\"") cfg.endpoint.dnsUpstreams)}]
  '';

  clientToml = pkgs.writeText "trusttunnel_client.toml" ''
    ${baseConfig}${directEndpointConfig}${tunListenerConfig}${socksListenerConfig}
  '';

  baseConfigFile = pkgs.writeText "trusttunnel-client-base.toml" baseConfig;

  listenerConfigFile = pkgs.writeText "trusttunnel-client-listener.toml" "${tunListenerConfig}${socksListenerConfig}";

  writeMergedConfig = ''
    ${pkgs.coreutils}/bin/cat ${baseConfigFile} > ${runtimeConfig}
    printf '%s\n' "$ENDPOINT_SECTION" >> ${runtimeConfig}
    ${pkgs.coreutils}/bin/cat ${listenerConfigFile} >> ${runtimeConfig}
  '';

  mergeFromDeeplink = ''
    TMP_ENDPOINT=$(${pkgs.coreutils}/bin/mktemp)
    ${cfg.package}/bin/trusttunnel_client --setup-wizard \
      -m non-interactive \
      -d "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg (toString cfg.deeplinkFile)})" \
      --settings "$TMP_ENDPOINT"
    ENDPOINT_SECTION=$(${pkgs.gawk}/bin/awk '
      /^\[/ { in_endpoint = ($0 == "[endpoint]") }
      in_endpoint { print }
    ' "$TMP_ENDPOINT")
    if [ -z "$ENDPOINT_SECTION" ]; then
      echo "no [endpoint] section in the deeplink output" >&2
      exit 1
    fi
    ${writeMergedConfig}
    ${pkgs.coreutils}/bin/rm -f "$TMP_ENDPOINT"
  '';

  mergeFromFile = ''
    ENDPOINT_SECTION=$(${pkgs.gawk}/bin/awk '
      /^\[/ { in_endpoint = ($0 == "[endpoint]") }
      in_endpoint { print }
    ' ${lib.escapeShellArg (toString cfg.importConfigFile)})
    if [ -z "$ENDPOINT_SECTION" ]; then
      echo "no [endpoint] section in ${toString cfg.importConfigFile}" >&2
      exit 1
    fi
    ${writeMergedConfig}
  '';

  overrideCredentials = ''
    USERNAME=$(${pkgs.gnused}/bin/sed -n 's/^username[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1/p' ${lib.escapeShellArg (toString cfg.credentialsFile)})
    PASSWORD=$(${pkgs.gnused}/bin/sed -n 's/^password[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1/p' ${lib.escapeShellArg (toString cfg.credentialsFile)})
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
      echo "failed to read username/password from ${toString cfg.credentialsFile}" >&2
      exit 1
    fi
    ${pkgs.gawk}/bin/awk -v user="$USERNAME" -v pass="$PASSWORD" '
      /^\[/ { section = $0 }
      section == "[endpoint]" && /^username[[:space:]]*=/ { print "username = \"" user "\""; next }
      section == "[endpoint]" && /^password[[:space:]]*=/ { print "password = \"" pass "\""; next }
      { print }
    ' ${runtimeConfig} > ${runtimeConfig}.tmp
    ${pkgs.coreutils}/bin/mv ${runtimeConfig}.tmp ${runtimeConfig}
  '';

  preStart = lib.optionalString hasRuntimeSource ''
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname ${runtimeConfig})"
    ${lib.optionalString (cfg.deeplinkFile == null && cfg.importConfigFile == null) ''
      ${pkgs.coreutils}/bin/cp ${clientToml} ${runtimeConfig}
      ${pkgs.coreutils}/bin/chmod 600 ${runtimeConfig}
    ''}
    ${lib.optionalString (cfg.deeplinkFile != null) mergeFromDeeplink}
    ${lib.optionalString (cfg.importConfigFile != null) mergeFromFile}
    ${lib.optionalString (cfg.credentialsFile != null) overrideCredentials}
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
  };

  options.services.trusttunnel.client = {
    enable = lib.mkEnableOption "TrustTunnel VPN client";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.trusttunnel-client;
      defaultText = lib.literalExpression "pkgs.trusttunnel-client";
      description = "TrustTunnel client package to use.";
    };

    deeplinkFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/trusttunnel-deeplink";
      description = "Path to a file with a tt:// deeplink. The file is read at runtime, so it can come from sops.";
    };

    importConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = ./endpoint_config.toml;
      description = "Path to an endpoint_config.toml. The [endpoint] section is read at runtime.";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/trusttunnel-credentials";
      description = "Path to a TOML file with username and password. The values are read at runtime and override the endpoint section. This is the supported secret path. The file must be readable by the client service, which runs as root with a restricted capability set.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "info"
        "debug"
        "trace"
      ];
      default = "info";
      description = "Logging level.";
    };

    vpnMode = lib.mkOption {
      type = lib.types.enum [
        "general"
        "selective"
      ];
      default = "general";
      description = "Routing policy. general routes all traffic except exclusions. selective routes only exclusions through the VPN.";
    };

    exclusions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "192.168.0.0/16"
        "10.0.0.0/8"
        "*.example.com"
      ];
      description = "Domains and IPs to route according to vpnMode. Supports domain, wildcard, IP, and CIDR.";
    };

    exclusionsTcpEarlyAck = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Route connections to scannable ports through a fake upstream to read the TLS SNI before connecting. Makes exclusions work with a secure DNS resolver or wildcard entries.";
    };

    exclusionsPreresolve = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pre-resolve DNS-resolvable exclusions in the background so that excluded hosts are routed correctly without waiting for the first DNS response.";
    };

    exclusionsPreresolveMaxQueries = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = "Maximum number of exclusion domains to pre-resolve per cycle.";
    };

    exclusionsScannablePorts = lib.mkOption {
      type = lib.types.str;
      default = "443,80,8080,8008,853";
      example = "443,80,8080:8090,853";
      description = "Comma-separated ports considered scannable for domain extraction and exclusion matching. Supports ranges.";
    };

    postQuantum = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable post-quantum key exchange.";
    };

    killswitch = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Block traffic when the VPN connection is lost.";
      };
      allowPorts = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
        description = "Local ports to allow inbound while the killswitch is active.";
      };
    };

    endpoint = {
      hostname = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "vpn.example.com";
        description = "Endpoint hostname for TLS.";
      };

      addresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "192.168.1.100:443"
          "vpn.example.com:443"
        ];
        description = "Endpoint addresses as IP:port or hostname:port.";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Authentication username. Prefer credentialsFile.";
      };

      password = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Authentication password. Prefer credentialsFile.";
      };

      ipv6 = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether IPv6 traffic can be routed.";
      };

      clientRandom = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "TLS client random prefix or mask in hex.";
      };

      clientRandomAuthKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "TLS client random auth key in hex. When set, part of client_random is derived from this key, the SNI, and random bytes.";
      };

      skipVerification = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Skip endpoint certificate verification.";
      };

      certificate = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to the endpoint certificate in PEM format.";
      };

      customSni = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "vpn.example.com";
        description = "Custom SNI override for the TLS handshake. It must match an allowed_sni or hostname in the endpoint hosts.toml.";
      };

      protocol = lib.mkOption {
        type = lib.types.enum [
          "http2"
          "http3"
        ];
        default = "http2";
        description = "Upstream protocol.";
      };

      tlsProfile = lib.mkOption {
        type = lib.types.enum [
          "chrome"
          "chrome_canary"
          "safari"
          "firefox"
          "okhttp"
          "openssl"
          "boringssl"
        ];
        default = "chrome";
        description = "TLS ClientHello fingerprint to mimic.";
      };

      antiDpi = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable anti-DPI measures.";
      };

      dnsUpstreams = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "tls://1.1.1.1"
          "https://dns.google/dns-query"
        ];
        description = "DNS resolvers for queries through the VPN. Empty uses AdGuard DNS.";
      };
    };

    listener = {
      tun = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable the TUN device listener.";
        };

        interface = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Network interface for the VPN. Auto-detected when empty.";
        };

        deviceName = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "TUN device name. Empty lets the kernel assign one.";
        };

        useExisting = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Attach to the existing device named by deviceName instead of creating one. Requires deviceName to be set.";
        };

        includedRoutes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "0.0.0.0/0"
            "2000::/3"
          ];
          description = "Routes to set on the virtual interface.";
        };

        excludedRoutes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "0.0.0.0/8"
            "10.0.0.0/8"
            "169.254.0.0/16"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "224.0.0.0/3"
          ];
          description = "Routes to exclude from the VPN.";
        };

        mtu = lib.mkOption {
          type = lib.types.int;
          default = 1280;
          description = "MTU size on the virtual interface.";
        };

        tcpRecvBufferSize = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = "TCP receive window size in bytes. 0 uses the optimized default.";
        };

        tcpSendBufferSize = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = "TCP send buffer size in bytes. 0 uses the optimized default.";
        };

        changeSystemDns = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Allow the client to change system DNS servers.";
        };
      };

      socks = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable the SOCKS5 proxy listener.";
        };

        address = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1:1080";
          description = "Address for the SOCKS5 proxy.";
        };

        username = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Username for SOCKS authentication.";
        };

        password = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Password for SOCKS authentication.";
        };
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra config.toml settings rendered as TOML. Use for keys not covered by typed options.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Raw TOML appended to config.toml after the generated settings.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.deeplinkFile != null && cfg.importConfigFile != null);
        message = "services.trusttunnel.client: only one of deeplinkFile or importConfigFile can be set.";
      }
      {
        assertion = !(cfg.deeplinkFile != null && cfg.credentialsFile != null);
        message = "services.trusttunnel.client: only one of deeplinkFile or credentialsFile can be set.";
      }
      {
        assertion =
          cfg.deeplinkFile != null
          || cfg.importConfigFile != null
          || (cfg.endpoint.hostname != "" && cfg.endpoint.addresses != [ ]);
        message = "services.trusttunnel.client: set endpoint.hostname and endpoint.addresses, or use deeplinkFile or importConfigFile.";
      }
      {
        assertion = !cfg.listener.tun.useExisting || cfg.listener.tun.deviceName != "";
        message = "services.trusttunnel.client.listener.tun: useExisting requires deviceName.";
      }
    ];

    warnings =
      lib.optional
        (cfg.credentialsFile == null && (cfg.endpoint.username != "" || cfg.endpoint.password != ""))
        "services.trusttunnel.client.endpoint.username/password are stored in the Nix store. Use credentialsFile instead.";

    systemd.services.trusttunnel-client = {
      description = "TrustTunnel VPN Client";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      preStart = preStart;

      serviceConfig = {
        Type = "simple";
        ExecStart =
          if hasRuntimeSource then
            "${cfg.package}/bin/trusttunnel_client --config ${runtimeConfig}"
          else
            "${cfg.package}/bin/trusttunnel_client --config ${clientToml}";
        Restart = "always";
        RestartSec = "5s";

        CapabilityBoundingSet = "CAP_NET_ADMIN CAP_NET_RAW";
        AmbientCapabilities = "CAP_NET_ADMIN";

        PrivateDevices = false;
        DeviceAllow = [ "/dev/net/tun rw" ];

        Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = lib.optional cfg.listener.tun.changeSystemDns "/etc/resolv.conf";

        RuntimeDirectory = lib.optional hasRuntimeSource "trusttunnel-client";
        RuntimeDirectoryMode = "0700";
        RuntimeDirectoryPreserve = false;
        UMask = "0077";
      };
    };
  };
}

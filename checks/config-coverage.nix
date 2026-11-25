{
  lib,
  pkgs,
  trusttunnel-endpoint,
  trusttunnel-client,
  endpointModule,
  clientModule,
  system ? pkgs.stdenv.hostPlatform.system,
}:

let
  # The client configuration is parsed by the client, which is a prebuilt
  # binary. The package source follows the client version, so a client update
  # without a matching source hash fails here instead of silently validating an
  # old schema.
  clientSrc = trusttunnel-client.clientSrc;

  # A schema probe, not a runnable configuration: it enables every listener
  # kind and both forward protocols so that every typed key is emitted. The
  # check compares keys. It does not evaluate runtime assertions or start a
  # service. The VM tests cover valid listener and forward-protocol choices.
  evaluated = lib.nixosSystem {
    # `nixpkgs.hostPlatform` below selects the platform. Passing `system`
    # would only set the deprecated `nixpkgs.system` option.
    system = null;
    modules = [
      endpointModule
      clientModule
      {
        nixpkgs.hostPlatform = system;
        system.stateVersion = "26.05";

        services.trusttunnel.endpoint = {
          enable = true;
          package = trusttunnel-endpoint;
          ipv6Available = true;
          allowPrivateNetwork = true;
          openFirewall = false;
          timeouts = {
            tlsHandshake = 11;
            clientListener = 601;
            connectionEstablishment = 31;
            tcpConnection = 604801;
            udpConnection = 301;
          };
          tls = {
            selfSigned.enable = true;
            mainHosts = [
              {
                hostname = "vpn.example.com";
                allowedSni = [ "cdn.example.com" ];
              }
            ];
            pingHosts = [ { hostname = "ping.example.com"; } ];
            speedtestHosts = [ { hostname = "speed.example.com"; } ];
            reverseProxyHosts = [
              {
                hostname = "proxy.example.com";
                allowedSni = [ "cdn.example.com" ];
              }
            ];
          };
          credentialsFile = pkgs.writeText "credentials.toml" "";
          speedtest.enable = true;
          speedtest.path = "/speed";
          ping.enable = true;
          ping.path = "/ping";
          auth.failureStatusCode = 403;
          auth.nonConnectFailureStatusCode = 404;
          defaultMaxHttp2ConnsPerClient = 8;
          defaultMaxHttp3ConnsPerClient = 1;
          protocols = {
            http1.uploadBufferSize = 32769;
            http2 = {
              initialConnectionWindowSize = 8388609;
              initialStreamWindowSize = 131073;
              maxConcurrentStreams = 1001;
              maxFrameSize = 16385;
              headerTableSize = 65537;
            };
            quic = {
              recvUdpPayloadSize = 1351;
              sendUdpPayloadSize = 1351;
              initialMaxData = 104857601;
              initialMaxStreamDataBidiLocal = 1048577;
              initialMaxStreamDataBidiRemote = 1048577;
              initialMaxStreamDataUni = 1048577;
              initialMaxStreamsBidi = 4097;
              initialMaxStreamsUni = 4097;
              maxConnectionWindow = 25165825;
              maxStreamWindow = 16777217;
              disableActiveMigration = true;
              enableEarlyData = true;
              messageQueueCapacity = 4097;
            };
          };
          reverseProxy = {
            enable = true;
            serverAddress = "127.0.0.1:81";
            pathMask = "/";
            h3BackwardCompatibility = true;
          };
          metrics = {
            enable = true;
            address = "127.0.0.1:1988";
            requestTimeout = 4;
            perClientMetrics = true;
          };
          icmp = {
            enable = true;
            interfaceName = "eth0";
            requestTimeout = 4;
            recvMessageQueueCapacity = 257;
          };
          forwardProtocol = {
            direct.enable = true;
            socks5 = {
              enable = true;
              address = "127.0.0.1:1081";
              extendedAuth = true;
            };
          };
          rulesFile = pkgs.writeText "rules.toml" "";
          subscription = {
            enable = true;
            hostname = "vpn.example.com";
            path = "/subscription";
            address = "203.0.113.1:443";
            name = "Example";
            dnsUpstreams = [ "tls://1.1.1.1" ];
            customSni = "cdn.example.com";
            clientRandomPrefix = "a0b0/f0f0";
          };
        };

        services.trusttunnel.client = {
          enable = true;
          package = trusttunnel-client;
          logLevel = "debug";
          vpnMode = "selective";
          exclusions = [ "192.168.0.0/16" ];
          exclusionsTcpEarlyAck = true;
          exclusionsPreresolve = true;
          exclusionsPreresolveMaxQueries = 51;
          exclusionsScannablePorts = "443,8443";
          postQuantum = true;
          killswitch = {
            enable = true;
            allowPorts = [ 4242 ];
          };
          endpoint = {
            hostname = "vpn.example.com";
            addresses = [ "203.0.113.1:443" ];
            ipv6 = true;
            clientRandom = "a0b0/f0f0";
            clientRandomAuthKey = "0123456789abcdef";
            skipVerification = true;
            certificate = "/etc/ssl/cert.pem";
            customSni = "cdn.example.com";
            protocol = "http3";
            tlsProfile = "firefox";
            antiDpi = true;
            dnsUpstreams = [ "tls://1.1.1.1" ];
          };
          listener.tun = {
            enable = true;
            interface = "tun0";
            deviceName = "tun9";
            useExisting = true;
            includedRoutes = [ "0.0.0.0/0" ];
            excludedRoutes = [ "192.168.0.0/16" ];
            mtu = 1300;
            tcpRecvBufferSize = 65536;
            tcpSendBufferSize = 65536;
            changeSystemDns = true;
          };
          listener.socks = {
            enable = true;
            address = "127.0.0.1:1082";
            username = "user";
            password = "pass";
          };
        };
      }
    ];
  };

  config = evaluated.config;
  split = lib.splitString " ";

  endpointExec = split config.systemd.services.trusttunnel-endpoint.serviceConfig.ExecStart;
  clientExec = split config.systemd.services.trusttunnel-client.serviceConfig.ExecStart;

  # trusttunnel_endpoint <vpn.toml> <hosts.toml>
  # trusttunnel_client --config <config.toml>
  endpointVpn = lib.elemAt endpointExec 1;
  endpointHosts = lib.elemAt endpointExec 2;
  clientToml = lib.elemAt clientExec 2;
in
assert lib.length endpointExec == 3;
assert lib.length clientExec == 3;
pkgs.runCommand "config-coverage"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    python3 ${./config-coverage.py} \
      ${trusttunnel-endpoint.src} \
      ${clientSrc} \
      ${endpointVpn} \
      ${endpointHosts} \
      ${clientToml}
    touch $out
  ''

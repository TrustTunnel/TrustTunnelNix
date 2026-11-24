{
  pkgs,
  trusttunnel-endpoint,
  endpointModule,
}:

pkgs.testers.nixosTest {
  name = "trusttunnel-endpoint";

  nodes.machine =
    { ... }:
    {
      imports = [ endpointModule ];

      services.trusttunnel.endpoint = {
        enable = true;
        package = trusttunnel-endpoint;
        listenAddress = "0.0.0.0:8443";
        openFirewall = true;
        credentialsFile = "/etc/trusttunnel-credentials.toml";
        tls.selfSigned.enable = true;
        tls.mainHosts = [ { hostname = "vpn.test"; } ];
        metrics.enable = true;
        metrics.address = "127.0.0.1:1987";
      };

      environment.etc."trusttunnel-credentials.toml" = {
        text = ''
          [[client]]
          username = "test"
          password = "secret"
        '';
        mode = "0400";
        user = "trusttunnel";
        group = "trusttunnel";
      };

      virtualisation.memorySize = 1024;
      virtualisation.cores = 2;
    };

  testScript = ''
    machine.wait_for_unit("trusttunnel-endpoint.service")
    machine.wait_for_open_port(8443)
    machine.succeed("test -s /var/lib/trusttunnel/certs/vpn.test/cert.pem")
    machine.succeed(
        "${pkgs.openssl}/bin/openssl s_client -connect 127.0.0.1:8443 "
        "-servername vpn.test </dev/null 2>/dev/null | grep -q 'CN *= *vpn.test'"
    )
    machine.wait_until_succeeds(
        "${pkgs.curl}/bin/curl -fsS http://127.0.0.1:1987/metrics | grep -q client_sessions",
        timeout=30,
    )
    machine.succeed("${pkgs.nftables}/bin/nft list ruleset | grep -q 8443")
    machine.succeed("systemctl reload trusttunnel-endpoint.service")
    machine.wait_for_unit("trusttunnel-endpoint.service")
  '';
}

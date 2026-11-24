{
  pkgs,
  trusttunnel-endpoint,
  trusttunnel-client,
  endpointModule,
  clientModule,
}:

pkgs.testers.nixosTest {
  name = "trusttunnel-client";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [
        endpointModule
        clientModule
      ];

      services.trusttunnel.endpoint = {
        enable = true;
        package = trusttunnel-endpoint;
        listenAddress = "127.0.0.1:8443";
        allowPrivateNetwork = true;
        credentialsFile = "/etc/trusttunnel-endpoint-credentials.toml";
        tls.selfSigned.enable = true;
        tls.mainHosts = [ { hostname = "vpn.test"; } ];
      };

      services.trusttunnel.client = {
        enable = true;
        package = trusttunnel-client;
        credentialsFile = "/etc/trusttunnel-client-credentials.toml";
        endpoint = {
          hostname = "vpn.test";
          addresses = [ "127.0.0.1:8443" ];
          username = "";
          password = "";
          skipVerification = true;
        };
        listener.tun.enable = false;
        listener.socks.enable = true;
        listener.socks.address = "127.0.0.1:1080";
        killswitch.enable = false;
      };

      environment.etc."trusttunnel-endpoint-credentials.toml" = {
        text = ''
          [[client]]
          username = "test"
          password = "secret"
        '';
        mode = "0400";
        user = "trusttunnel";
        group = "trusttunnel";
      };

      environment.etc."trusttunnel-client-credentials.toml" = {
        text = ''
          [[client]]
          username = "test"
          password = "secret"
        '';
        mode = "0400";
        user = "root";
        group = "root";
      };

      systemd.services.httpserver = {
        wantedBy = [ "multi-user.target" ];
        script = "${pkgs.python3}/bin/python3 -m http.server 8080 --directory ${pkgs.writeTextDir "hello.txt" "hello"}";
      };

      virtualisation.memorySize = 1024;
      virtualisation.cores = 2;
    };

  testScript = ''
    machine.wait_for_unit("trusttunnel-endpoint.service", timeout=60)
    machine.wait_for_open_port(8443, timeout=30)
    try:
        machine.wait_for_unit("trusttunnel-client.service", timeout=30)
    except Exception:
        print(machine.succeed("systemctl status trusttunnel-client.service --no-pager || true"))
        print(machine.succeed("journalctl -u trusttunnel-client --no-pager | tail -100 || true"))
        raise
    machine.wait_for_open_port(1080, timeout=30)
    machine.wait_for_open_port(8080, timeout=30)
    machine.wait_until_succeeds(
        "${pkgs.curl}/bin/curl -fsS --socks5 127.0.0.1:1080 "
        "http://127.0.0.1:8080/hello.txt | grep -qx hello",
        timeout=60,
    )
  '';
}

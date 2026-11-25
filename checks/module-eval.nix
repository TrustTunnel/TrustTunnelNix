{
  lib,
  pkgs,
  nixosModules,
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  evaluated = lib.nixosSystem {
    system = null;
    modules = [
      nixosModules.default
      {
        nixpkgs.hostPlatform = system;
        system.stateVersion = "26.05";

        services.trusttunnel.endpoint = {
          enable = true;
          credentials = [
            {
              username = "test";
              password = "test";
            }
          ];
          tls.acme = {
            enable = true;
            email = "admin@example.com";
          };
          tls.mainHosts = [ { hostname = "vpn.example.com"; } ];
          tls.pingHosts = [ { hostname = "ping.example.com"; } ];
          tls.speedtestHosts = [ { hostname = "speed.example.com"; } ];
          tls.reverseProxyHosts = [ { hostname = "proxy.example.com"; } ];
          reverseProxy.enable = true;
        };

        services.trusttunnel.client = {
          enable = true;
          endpoint = {
            hostname = "vpn.example.com";
            addresses = [ "127.0.0.1:8443" ];
            username = "test";
            password = "test";
          };
          listener.tun.enable = false;
          listener.socks.enable = true;
        };
      }
    ];
  };

  endpointExec = evaluated.config.systemd.services.trusttunnel-endpoint.serviceConfig.ExecStart;
  clientExec = evaluated.config.systemd.services.trusttunnel-client.serviceConfig.ExecStart;

  expectedAcmeCerts = [
    "ping.example.com"
    "proxy.example.com"
    "speed.example.com"
    "vpn.example.com"
  ];
  acmeCerts = builtins.attrNames evaluated.config.security.acme.certs;
in
assert expectedAcmeCerts == acmeCerts;
pkgs.runCommand "module-eval" { } ''
  test -n "${endpointExec}"
  test -n "${clientExec}"
  touch $out
''

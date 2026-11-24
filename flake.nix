{
  description = "Nix packages for the TrustTunnel VPN protocol";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          trusttunnel-endpoint = pkgs.callPackage ./pkgs/trusttunnel-endpoint.nix { };
          trusttunnel-client = pkgs.callPackage ./pkgs/trusttunnel-client.nix { };
          default = self.packages.${system}.trusttunnel-endpoint;
        }
      );

      overlays.default = final: _prev: {
        trusttunnel-endpoint = final.callPackage ./pkgs/trusttunnel-endpoint.nix { };
        trusttunnel-client = final.callPackage ./pkgs/trusttunnel-client.nix { };
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);

      checks = forAllSystems (system: {
        inherit (self.packages.${system}) trusttunnel-endpoint trusttunnel-client;
      });
    };
}

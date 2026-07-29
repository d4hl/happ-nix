{
  description = "Happ proxy desktop client (VLESS/VMess/Trojan/Shadowsocks) with a TUN daemon";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];

      forAllSystems = lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system: let
        pkgs = import nixpkgs { inherit system; };
      in {
        default = pkgs.callPackage ./happ.nix { inherit pkgs lib; };
        happ = pkgs.callPackage ./happ.nix { inherit pkgs lib; };
      });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/happ";
        };
      });

      overlays.default = final: prev: {
        happ = self.packages.${prev.stdenv.hostPlatform.system}.default;
      };

      nixosModules.default = { pkgs, ... }: {
        nixpkgs.overlays = [ self.overlays.default ];
        imports = [ ./happ-module.nix ];
      };
    };
}

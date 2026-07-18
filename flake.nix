{
  description = "Happ proxy desktop client (VLESS/VMess/Trojan/Shadowsocks) with a TUN daemon";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      happ = pkgs.callPackage ./happ.nix { inherit pkgs lib; };
    in
    {
      packages.${system} = {
        default = happ;
        happ = happ;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${happ}/bin/happ";
        };
      };

      overlays.default = final: prev: {
        happ = self.packages.${system}.default;
      };

      nixosModules.default = { pkgs, ... }: {
        nixpkgs.overlays = [ self.overlays.default ];
        imports = [ ./happ-module.nix ];
      };
    };
}

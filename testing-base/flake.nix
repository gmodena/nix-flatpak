# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flatpaks.url = "../";
  };
  outputs = inputs@{ self, nixpkgs, flatpaks, ... }:
    let
      system = "x86_64-linux";
    in
    {
      # hostname = test-system-module
      nixosConfigurations.test-system-module = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          flatpaks.nixosModules.nix-flatpak
          ./configuration.nix
        ];
      };
    };
}

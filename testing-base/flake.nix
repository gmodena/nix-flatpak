# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    home-manager.url = "github:nix-community/home-manager/release-23.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    flatpaks.url = "../";
  };
  outputs = inputs@{ self, nixpkgs, home-manager, flatpaks, ... }:
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

      # hostname = test-hm-module
      nixosConfigurations.test-hm-module = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./common.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs.flake-inputs = inputs;
            home-manager.users."antani".imports = [
              flatpaks.homeManagerModules.nix-flatpak
              ./flatpak.nix
            ];
            home-manager.users.antani.home.stateVersion = "23.11";
          }
        ];
      };
    };
}

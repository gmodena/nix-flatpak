# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    hjem.url = "github:feel-co/hjem";
    hjem.inputs.nixpkgs.follows = "nixpkgs";
    hjem.inputs.nix-darwin.follows = "";
    flatpaks.url = "../";
  };
  outputs = inputs@{ nixpkgs, home-manager, hjem, flatpaks, ... }:
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
          ./flatpak.nix
        ];
      };

      # hostname = test-hm-module
      nixosConfigurations.test-hm-module = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
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
          ./configuration.nix
        ];
      };

      # hostname = test-hjem-module
      nixosConfigurations.test-hjem-module = nixpkgs.lib.nixosSystem {
        inherit system;
        module = [
          hjem.nixosModules.default
          ./configuration.nix
          {
            config.hjem = {
              extraModules = [
                flatpaks.hjmeModules.flatpak
                ./flatpak.nix
              ];
              users.alice.services.flatpak.enable = true;
            };
          }
        ];
      };
    };
}

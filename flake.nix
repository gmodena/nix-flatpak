{
  description = "Manage flatpak apps declaratively.";

  outputs = _: rec {
    nixosModules = rec {
      nix-flatpak = ./modules/nixos.nix;
      default = nix-flatpak;
    };
    homeManagerModules = rec {
      nix-flatpak = ./modules/home-manager.nix;
      default = nix-flatpak;
    };
    homeModules = homeManagerModules;
  };
}

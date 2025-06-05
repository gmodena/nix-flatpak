{
  description = "Manage flatpak apps declaratively.";

  outputs = _:
    {
      nixosModules = { nix-flatpak = ./modules/nixos.nix; };
      homeManagerModules = { nix-flatpak = ./modules/home-manager.nix; };
    };
}

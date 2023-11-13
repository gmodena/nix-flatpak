{
  description = "Manage flatpak apps declaratively.";

  outputs = _:
    {
      nixosModules = { nix-flatpak = import ./modules/nixos.nix; };
      homeManagerModules = { nix-flatpak = import ./modules/home-manager.nix; };
    };
}

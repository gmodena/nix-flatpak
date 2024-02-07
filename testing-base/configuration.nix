# configuration.nix
{ config, lib, pkgs, ... }: {
  imports = [
    ./common.nix
  ];
  # nix-flatpak setup
  services.flatpak.enable = true;
  services.flatpak.update.auto.enable = false;
  services.flatpak.uninstallUnmanagedPackages = true;
  services.flatpak.packages = [
    # ...
  ];
}

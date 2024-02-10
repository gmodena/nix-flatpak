# configuration.nix
{ config, lib, pkgs, ... }: {
  imports = [
    ./common.nix
    ./flatpak.nix
  ];
}

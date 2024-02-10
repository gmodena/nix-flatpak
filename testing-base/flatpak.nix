# home.nix
{ lib, ... }: {

# nix-flatpak setup
services.flatpak.enable = true;

services.flatpak.remotes = lib.mkOptionDefault [{
name = "flathub-beta";
location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
}];

services.flatpak.update.auto.enable = false;
services.flatpak.uninstallUnmanagedPackages = true;
services.flatpak.packages = [
  { appId = "com.brave.Browser"; origin = "flathub";  }
  "com.obsproject.Studio"
  "im.riot.Riot"
];

}

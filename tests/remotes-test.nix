{ pkgs ? import <nixpkgs> { } }:

let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  installation = "system";
  installer = import ../modules/flatpak/remotes.nix { inherit pkgs; };
in
runTests {
  testMkFlatpakAddRemotesCmd = {
    expr = installer.mkFlatpakAddRemotesCmd installation [{ name = "flathub"; location = "http://flathub"; }];
    expected = "if ! ${pkgs.flatpak}/bin/flatpak remotes --system --columns=name | ${pkgs.gnugrep}/bin/grep -q '^flathub$'; then\n  ${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists   flathub http://flathub\nfi\n";
  };

  testMkFlatpakAddRemotesCmdCmdWithTrustedKeys = {
    expr = installer.mkFlatpakAddRemotesCmd installation [{ name = "flathub"; location = "http://flathub"; gpg-import = "trustedkeys.gpg"; }];
    expected = "if ! ${pkgs.flatpak}/bin/flatpak remotes --system --columns=name | ${pkgs.gnugrep}/bin/grep -q '^flathub$'; then\n  ${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists  --gpg-import=trustedkeys.gpg flathub http://flathub\nfi\n";
  };
}

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
    expected = "${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists   flathub http://flathub\n";
  };

  testMkFlatpakAddRemotesCmdCmdWithTrustedKeys = {
    expr = installer.mkFlatpakAddRemotesCmd installation [{ name = "flathub"; location = "http://flathub"; gpg-import = "trustedkeys.gpg"; }];
    expected = "${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists  --gpg-import=trustedkeys.gpg flathub http://flathub\n";
  };
}

# Updates should be performed during activation when the installer is
# executed at service start. They should not be performed when
# the installer is executed by a timer.
{ pkgs ? import <nixpkgs> { } }:

let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  installation = "user";

  flatpakConfig = import ./config.nix;
  flatpakFilePath = "/path/to/some/app.flatpak";
  cfg = flatpakConfig // {
    packages = [
      {
        appId = "noop"; # appId is required here because we are injecting from the test suite without resolving options.nix defaults.
        path = flatpakFilePath;
      }
    ];
  };

  install = import ../modules/flatpak/install.nix { inherit cfg pkgs lib installation; executionContext = "service-start"; };
in
runTests {
  testInstall = {
    expr = install.mkInstallCmd;
    expected = "${pkgs.flatpak}/bin/flatpak --${installation} install --noninteractive ${flatpakFilePath}";
  };
}

# Updates should be performed during activation when the installer is
# executed at service start. They should not be performed when
# the installer is executed by a timer.
{ pkgs ? import <nixpkgs> { } }:

let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  installation = "system";

  flatpakConfig = import ./config.nix;
  cfg = flatpakConfig // {
    update = flatpakConfig.update // {
      onActivation = true;
    };
  };

  serviceStartExecutionContext = import ../modules/flatpak/install.nix { inherit cfg pkgs lib installation; executionContext = "service-start"; };
  timerExecutionContext = import ../modules/flatpak/install.nix { inherit cfg pkgs lib installation; executionContext = "timer"; };
in
runTests {
  testDoNotUpdate = {
    # invoke the installer from a timer, when update.auto is disabled but update.onActivation is enabled.
    # Packages won't be updated.
    expr = timerExecutionContext.mkInstallCmd;
    expected = "${pkgs.flatpak}/bin/flatpak --system --noninteractive    install   some-remote SomeAppId \n";
  };

  testUpdate = {
    # invoke the installer at service start, when update.auto is disabled but update.onActivation is enabled.
    # Packages will be updated.
    expr = serviceStartExecutionContext.mkInstallCmd;
    expected = "${pkgs.flatpak}/bin/flatpak --system --noninteractive  --or-update   install   some-remote SomeAppId \n";
  };
}

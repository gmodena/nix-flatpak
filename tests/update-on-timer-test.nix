{ pkgs ? import <nixpkgs> { } }:

let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  installation = "system";

  flatpakConfig = import ./config.nix;
  cfg = flatpakConfig // {
    update = flatpakConfig.update // {
      auto = {
        enable = true;
      };
    };
  };

  timerExecutionContext = import ../modules/flatpak/install.nix { inherit cfg pkgs lib installation; executionContext = "timer"; };
  serviceStartExecutionContext = import ../modules/flatpak/install.nix { inherit cfg pkgs lib installation; executionContext = "service-start"; };
in
runTests {
  testDoNotUpdate = {
    # invoke the installer on activation, when update.auto is enabled but update.onActivation is disabled.
    # Packages won't be updated.
    expr = serviceStartExecutionContext.mkInstallCmd;
    expected = "${pkgs.flatpak}/bin/flatpak --system --noninteractive    install   some-remote SomeAppId \n";
  };

  testUpdate = {
    # invoke the installer from a timer, when update.auto is enabled but update.onActivation is disabled.
    # Packages will be updated.
    expr = timerExecutionContext.mkInstallCmd;
    expected = "${pkgs.flatpak}/bin/flatpak --system --noninteractive  --or-update   install   some-remote SomeAppId \n";
  };
}

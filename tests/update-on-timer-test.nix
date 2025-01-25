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
    expected = "if ${pkgs.jq}/bin/jq -r -n --argjson old \"$OLD_STATE\" --arg appId \"SomeAppId\" '$old.packages | index($appId) != null' | ${pkgs.gnugrep}/bin/grep -q true; then\n  if [[ -n \"\" ]] && [[ \"$( ${pkgs.flatpak}/bin/flatpak --system info \"SomeAppId\" --show-commit 2>/dev/null )\" != \"\" ]]; then\n    \n    : # No operation if no update command needs to run.\n  fi\nelse\n  ${pkgs.flatpak}/bin/flatpak --system --noninteractive install  some-remote SomeAppId\n\n\n  : # No operation if no install command needs to run.\nfi\n";
  };

  testUpdate = {
    # invoke the installer from a timer, when update.auto is enabled but update.onActivation is disabled.
    # Packages will be updated.
    expr = timerExecutionContext.mkInstallCmd;
    expected = "${pkgs.flatpak}/bin/flatpak --system --noninteractive install --or-update some-remote SomeAppId\n\n";
  };
}

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
    expected =  "# Check if app exists in old state, handling both formats\nif $( ${pkgs.jq}/bin/jq -r -n --argjson old \"$OLD_STATE\" --arg appId \"SomeAppId\" --from-file ${../modules/flatpak/state/app_exists.jq} | ${pkgs.gnugrep}/bin/grep -q true ); then\n  # App exists in old state, check if commit changed\n  if [[ -n \"\" ]] && [[ \"$( ${pkgs.flatpak}/bin/flatpak --system info \"SomeAppId\" --show-commit 2>/dev/null )\" != \"\" ]]; then\n    \n    : # No operation if no install command needs to run.\n  fi\nelse\n  ${pkgs.flatpak}/bin/flatpak --system --noninteractive install  some-remote SomeAppId\n\n\n  : # No operation if no install command needs to run.\nfi\n";
  };

  testUpdate = {
    # invoke the installer at service start, when update.auto is disabled but update.onActivation is enabled.
    # Packages will be updated.
    expr = serviceStartExecutionContext.mkInstallCmd;
    expected = "${pkgs.flatpak}/bin/flatpak --system --noninteractive install --or-update some-remote SomeAppId\n\n";
  };
}

# Updates should be performed during activation when the installer is
# executed at service start. They should not be performed when
# the installer is executed by a timer.
{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  installation = "user";
  flatpakConfig = import ./config.nix;
  flatpakBundle = "app-bundle.flatpak";
  cfg = flatpakConfig // {
    packages = [
      {
        appId = "noop"; # appId is required here because we are injecting from the test suite without resolving options.nix defaults.
        bundle = flatpakBundle;
      }
    ];
  };
  install = import ../modules/flatpak/install.nix { inherit cfg pkgs lib installation; executionContext = "service-start"; };
in
runTests {
  testInstall = {
    expr = install.mkInstallCmd;
    expected = ''if true; then
    # Check if sha256 changed between OLD_STATE and NEW_STATE
    changedSha256="$(${pkgs.jq}/bin/jq -ns \
      --argjson oldState "$OLD_STATE" \
      --argjson newState "$NEW_STATE" \
      --arg appId "noop" \
      -f ${../modules/flatpak/state/compare_sha.jq})"

    if [[ -n "$changedSha256" ]]; then
      if ${pkgs.flatpak}/bin/flatpak --user info "noop" &>/dev/null; then
        ${pkgs.flatpak}/bin/flatpak --user uninstall -y "noop"
        : # No operation if no install command needs to run.
      fi
      ${pkgs.flatpak}/bin/flatpak --user --noninteractive install --bundle app-bundle.flatpak
      : # No operation if no install command needs to run.
    fi
else
  # Check if app exists in old state, handling both formats
  if $( ${pkgs.jq}/bin/jq -r -n --argjson old "$OLD_STATE" --arg appId "noop" --from-file ${../modules/flatpak/state/app_exists.jq} | ${pkgs.gnugrep}/bin/grep -q true ); then
    # App exists in old state, check if commit changed
    if [[ -n "" ]] && [[ "$( ${pkgs.flatpak}/bin/flatpak --user info "noop" --show-commit 2>/dev/null )" != "" ]]; then
      
      : # No operation if no install command needs to run.
    fi
  else
    


    : # No operation if no install command needs to run.
  fi
fi
'';
  };
}
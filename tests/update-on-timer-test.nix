{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  installation = "system";
  flatpakConfig = import ./config.nix;
  
  # Configuration for service-start context (no updates on activation)
  serviceStartCfg = flatpakConfig // {
    update = flatpakConfig.update // {
      auto = {
        enable = true;
      };
      onActivation = false;  # This is key - disable updates on activation
    };
    packages = [
      { appId = "SomeAppId"; origin = "some-remote"; }
    ];
  };
  
  # Configuration for timer context (allows updates)
  timerCfg = flatpakConfig // {
    update = flatpakConfig.update // {
      auto = {
        enable = true;
      };
      onActivation = true;   # Enable updates for timer context
    };
    packages = [
      { appId = "SomeAppId"; origin = "some-remote"; }
    ];
  };
  
  timerExecutionContext = import ../modules/flatpak/install.nix { 
    cfg = timerCfg; 
    inherit pkgs lib installation; 
    executionContext = "timer"; 
  };
  
  serviceStartExecutionContext = import ../modules/flatpak/install.nix { 
    cfg = serviceStartCfg; 
    inherit pkgs lib installation; 
    executionContext = "service-start"; 
  };
in
runTests {
  testDoNotUpdate = {
    # invoke the installer on activation, when update.auto is enabled but update.onActivation is disabled.
    # Packages won't be updated.
    expr = serviceStartExecutionContext.mkInstallCmd;
    expected = ''if false; then
    # Check if sha256 changed between OLD_STATE and NEW_STATE
    changedSha256="$(${pkgs.jq}/bin/jq -ns \
      --argjson oldState "$OLD_STATE" \
      --argjson newState "$NEW_STATE" \
      --arg appId "SomeAppId" \
      -f ${../modules/flatpak/state/compare_sha.jq})"

    if [[ -n "$changedSha256" ]]; then
      if ${pkgs.flatpak}/bin/flatpak --system info "SomeAppId" &>/dev/null; then
        ${pkgs.flatpak}/bin/flatpak --system uninstall -y "SomeAppId"
        : # No operation if no install command needs to run.
      fi
      
      : # No operation if no install command needs to run.
    fi
else
  # Check if app exists in old state, handling both formats
  if $( ${pkgs.jq}/bin/jq -r -n --argjson old "$OLD_STATE" --arg appId "SomeAppId" --from-file ${../modules/flatpak/state/app_exists.jq} | ${pkgs.gnugrep}/bin/grep -q true ); then
    # App exists in old state, check if commit changed
    if [[ -n "" ]] && [[ "$( ${pkgs.flatpak}/bin/flatpak --system info "SomeAppId" --show-commit 2>/dev/null )" != "" ]]; then
      
      : # No operation if no install command needs to run.
    fi
  else
    ${pkgs.flatpak}/bin/flatpak --system --noninteractive install  some-remote SomeAppId


    : # No operation if no install command needs to run.
  fi
fi
'';
  };
  testUpdate = {
    # invoke the installer from a timer, when update.auto is enabled but update.onActivation is disabled.
    # Packages will be updated.
    expr = timerExecutionContext.mkInstallCmd;
    expected = ''if false; then
    # Check if sha256 changed between OLD_STATE and NEW_STATE
    changedSha256="$(${pkgs.jq}/bin/jq -ns \
      --argjson oldState "$OLD_STATE" \
      --argjson newState "$NEW_STATE" \
      --arg appId "SomeAppId" \
      -f ${../modules/flatpak/state/compare_sha.jq})"

    if [[ -n "$changedSha256" ]]; then
      if ${pkgs.flatpak}/bin/flatpak --system info "SomeAppId" &>/dev/null; then
        ${pkgs.flatpak}/bin/flatpak --system uninstall -y "SomeAppId"
        : # No operation if no install command needs to run.
      fi
      
      : # No operation if no install command needs to run.
    fi
else
  # Check if app exists in old state, handling both formats
  if $( ${pkgs.jq}/bin/jq -r -n --argjson old "$OLD_STATE" --arg appId "SomeAppId" --from-file ${../modules/flatpak/state/app_exists.jq} | ${pkgs.gnugrep}/bin/grep -q true ); then
    # App exists in old state, check if commit changed
    if [[ -n "" ]] && [[ "$( ${pkgs.flatpak}/bin/flatpak --system info "SomeAppId" --show-commit 2>/dev/null )" != "" ]]; then
      
      : # No operation if no install command needs to run.
    fi
  else
    ${pkgs.flatpak}/bin/flatpak --system --noninteractive install --or-update some-remote SomeAppId


    : # No operation if no install command needs to run.
  fi
fi
'';
  };
}
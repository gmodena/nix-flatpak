# Updates should be performed during activation when the installer is
# executed at service start. They should not be performed when
# the installer is executed by a timer.
{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  installation = "user";
  pwd = builtins.getEnv "PWD";
  flatpakrefUrl = "file://${pwd}/fixtures/package.flatpakref";
  flatpakrefSha256 = "040iig2yg2i28s5xc9cvp5syaaqq165idy3nhlpv8xn4f6zh4h1f";
  flatpakConfig = import ./config.nix;
  cfg = flatpakConfig // {
    packages = [
      {
        appId = "org.gnome.gedit"; # Fixed: should match the expected appId
        flatpakref = flatpakrefUrl;
        sha256 = flatpakrefSha256; # Fixed: corrected variable name
        commit = "abc123";
      }
      { appId = "SomeAppId"; origin = "some-remote"; }
    ];
  };
  install = import ../modules/flatpak/install.nix { inherit cfg pkgs lib installation; executionContext = "service-start"; };
in
runTests {
  testInstall = {
    expr = install.mkInstallCmd;
    expected = ''if false; then
    # Check if sha256 changed between OLD_STATE and NEW_STATE
    changedSha256="$(${pkgs.jq}/bin/jq -ns \
      --argjson oldState "$OLD_STATE" \
      --argjson newState "$NEW_STATE" \
      --arg appId "org.gnome.gedit" \
      -f ${../modules/flatpak/state/compare_sha.jq})"

    if [[ -n "$changedSha256" ]]; then
      if ${pkgs.flatpak}/bin/flatpak --user info "org.gnome.gedit" &>/dev/null; then
        ${pkgs.flatpak}/bin/flatpak --user uninstall -y "org.gnome.gedit"
        : # No operation if no install command needs to run.
      fi
      
      : # No operation if no install command needs to run.
    fi
else
  # Check if app exists in old state, handling both formats
  if $( ${pkgs.jq}/bin/jq -r -n --argjson old "$OLD_STATE" --arg appId "org.gnome.gedit" --from-file ${../modules/flatpak/state/app_exists.jq} | ${pkgs.gnugrep}/bin/grep -q true ); then
    # App exists in old state, check if commit changed
    if [[ -n "abc123" ]] && [[ "$( ${pkgs.flatpak}/bin/flatpak --user info "org.gnome.gedit" --show-commit 2>/dev/null )" != "abc123" ]]; then
      ${pkgs.flatpak}/bin/flatpak --user --noninteractive update --commit="abc123" org.gnome.gedit
      : # No operation if no install command needs to run.
    elif false; then
      ${pkgs.flatpak}/bin/flatpak --user --noninteractive install  $(if ${pkgs.flatpak}/bin/flatpak --user list --app --columns=application | ${pkgs.gnugrep}/bin/grep -q org.gnome.gedit; then
    echo "gedit-origin org.gnome.gedit"
else
    echo "--from ${flatpakrefUrl}"
fi)

${pkgs.flatpak}/bin/flatpak --user --noninteractive update --commit="abc123" org.gnome.gedit

      : # No operation if no install command needs to run.
    fi
  else
    ${pkgs.flatpak}/bin/flatpak --user --noninteractive install  $(if ${pkgs.flatpak}/bin/flatpak --user list --app --columns=application | ${pkgs.gnugrep}/bin/grep -q org.gnome.gedit; then
    echo "gedit-origin org.gnome.gedit"
else
    echo "--from ${flatpakrefUrl}"
fi)

${pkgs.flatpak}/bin/flatpak --user --noninteractive update --commit="abc123" org.gnome.gedit

    : # No operation if no install command needs to run.
  fi
fi
if false; then
    # Check if sha256 changed between OLD_STATE and NEW_STATE
    changedSha256="$(${pkgs.jq}/bin/jq -ns \
      --argjson oldState "$OLD_STATE" \
      --argjson newState "$NEW_STATE" \
      --arg appId "SomeAppId" \
      -f ${../modules/flatpak/state/compare_sha.jq})"

    if [[ -n "$changedSha256" ]]; then
      if ${pkgs.flatpak}/bin/flatpak --user info "SomeAppId" &>/dev/null; then
        ${pkgs.flatpak}/bin/flatpak --user uninstall -y "SomeAppId"
        : # No operation if no install command needs to run.
      fi
      
      : # No operation if no install command needs to run.
    fi
else
  # Check if app exists in old state, handling both formats
  if $( ${pkgs.jq}/bin/jq -r -n --argjson old "$OLD_STATE" --arg appId "SomeAppId" --from-file ${../modules/flatpak/state/app_exists.jq} | ${pkgs.gnugrep}/bin/grep -q true ); then
    # App exists in old state, check if commit changed
    if [[ -n "" ]] && [[ "$( ${pkgs.flatpak}/bin/flatpak --user info "SomeAppId" --show-commit 2>/dev/null )" != "" ]]; then
      
      : # No operation if no install command needs to run.
    elif false; then
      ${pkgs.flatpak}/bin/flatpak --user --noninteractive install  some-remote SomeAppId


      : # No operation if no install command needs to run.
    fi
  else
    ${pkgs.flatpak}/bin/flatpak --user --noninteractive install  some-remote SomeAppId


    : # No operation if no install command needs to run.
  fi
fi
'';
  };
}
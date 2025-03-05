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
  flatpakrefSha251 = "040iig2yg2i28s5xc9cvp5syaaqq165idy3nhlpv8xn4f6zh4h1f";

  flatpakConfig = import ./config.nix;
  cfg = flatpakConfig // {
    packages = [
      {
        appId = "noop"; # appId is required here because we are injecting from the test suite without resolving options.nix defaults. 
        flatpakref = flatpakrefUrl;
        sha256 = flatpakrefSha251;
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
    expected = "# Check if app exists in old state, handling both formats\nif $( ${pkgs.jq}/bin/jq -r -n --argjson old \"$OLD_STATE\" --arg appId \"org.gnome.gedit\" --from-file ${../modules/flatpak/state/app_exists.jq} | ${pkgs.gnugrep}/bin/grep -q true ); then\n  # App exists in old state, check if commit changed\n  if [[ -n \"abc123\" ]] && [[ \"$( ${pkgs.flatpak}/bin/flatpak --user info \"org.gnome.gedit\" --show-commit 2>/dev/null )\" != \"abc123\" ]]; then\n    ${pkgs.flatpak}/bin/flatpak --user --noninteractive update --commit=\"abc123\" org.gnome.gedit\n    : # No operation if no install command needs to run.\n  fi\nelse\n  ${pkgs.flatpak}/bin/flatpak --user --noninteractive install  $(if ${pkgs.flatpak}/bin/flatpak --user list --app --columns=application | ${pkgs.gnugrep}/bin/grep -q org.gnome.gedit; then\n    echo \"gedit-origin org.gnome.gedit\"\nelse\n    echo \"--from ${flatpakrefUrl}\"\nfi)\n\n${pkgs.flatpak}/bin/flatpak --user --noninteractive update --commit=\"abc123\" org.gnome.gedit\n\n  : # No operation if no install command needs to run.\nfi\n# Check if app exists in old state, handling both formats\nif $( ${pkgs.jq}/bin/jq -r -n --argjson old \"$OLD_STATE\" --arg appId \"SomeAppId\" --from-file ${../modules/flatpak/state/app_exists.jq} | ${pkgs.gnugrep}/bin/grep -q true ); then\n  # App exists in old state, check if commit changed\n  if [[ -n \"\" ]] && [[ \"$( ${pkgs.flatpak}/bin/flatpak --user info \"SomeAppId\" --show-commit 2>/dev/null )\" != \"\" ]]; then\n    \n    : # No operation if no install command needs to run.\n  fi\nelse\n  ${pkgs.flatpak}/bin/flatpak --user --noninteractive install  some-remote SomeAppId\n\n\n  : # No operation if no install command needs to run.\nfi\n";
  };
}

{ cfg, pkgs, lib, installation ? "system", ... }:

let
  # Put the state file in the `gcroots` folder of the respective installation,
  # which prevents it from being garbage collected. This could probably be
  # improved in the future if there are better conventions for how this should
  # be handled. Right now it introduces a small issue of the state file derivation
  # not being garbage collected even when this module is removed. You can find
  # more details on this design drawback in PR#23
  gcroots =
    if (installation == "system")
    then "/nix/var/nix/gcroots/"
    else "\${XDG_STATE_HOME:-$HOME/.local/state}/home-manager/gcroots";
  stateFile = pkgs.writeText "flatpak-state.json" (builtins.toJSON {
    packages = map (builtins.getAttr "appId") cfg.packages;
  });
  statePath = "${gcroots}/${stateFile.name}";

  updateApplications = cfg.update.onActivation || cfg.update.auto.enable;

  handleUnmanagedPackagesCmd = installation: uninstallUnmanagedPackages:
    lib.optionalString uninstallUnmanagedPackages ''
      # Add all installed Flatpak packages to the old state, so only the managed ones (new state) will be kept
      INSTALLED_PACKAGES=$(${pkgs.flatpak}/bin/flatpak --${installation} list --app --columns=application)
      OLD_STATE=$(${pkgs.jq}/bin/jq -r -n \
        --argjson old "$OLD_STATE" \
        --arg installed_packages "$INSTALLED_PACKAGES" \
        '$old + { "packages" : $installed_packages | split("\n") }')
    '';

  flatpakUninstallCmd = installation: {}: ''
    # Uninstall all packages that are present in the old state but not the new one
    ${pkgs.jq}/bin/jq -r -n \
      --argjson old "$OLD_STATE" \
      --argjson new "$NEW_STATE" \
      '($old.packages - $new.packages)[]' \
      | while read -r APP_ID; do
          ${pkgs.flatpak}/bin/flatpak uninstall --${installation} -y $APP_ID
        done
  '';

  flatpakInstallCmd = installation: update: { appId, origin ? "flathub", commit ? null, ... }: ''
    ${pkgs.flatpak}/bin/flatpak --${installation} --noninteractive --no-auto-pin install \
        ${if update && commit == null then ''--or-update'' else ''''} ${origin} ${appId}

    ${if commit == null
        then '' ''
        else ''${pkgs.flatpak}/bin/flatpak --${installation} update --noninteractive  --commit="${commit}" ${appId}
    ''}
  '';

  flatpakAddRemoteCmd = installation: { name, location, args ? null, ... }: ''
    ${pkgs.flatpak}/bin/flatpak remote-add --${installation} --if-not-exists ${if args == null then "" else args} ${name} ${location}
  '';
  flatpakAddRemote = installation: remotes: map (flatpakAddRemoteCmd installation) remotes;
  flatpakInstall = installation: update: packages: map (flatpakInstallCmd installation update) packages;

  mkFlatpakInstallCmd = installation: update: packages: builtins.foldl' (x: y: x + y) '''' (flatpakInstall installation update packages);
  mkFlatpakAddRemoteCmd = installation: remotes: builtins.foldl' (x: y: x + y) '''' (flatpakAddRemote installation remotes);
in
pkgs.writeShellScript "flatpak-managed-install" ''
  # This script is triggered at build time by a transient systemd unit.
  set -eu

  # Setup state variables
  NEW_STATE=$(cat ${stateFile})
  if [[ -f ${statePath} ]]; then
    OLD_STATE=$(cat ${statePath})
  else
    OLD_STATE={}
  fi

  # Handle unmanaged packages
  ${handleUnmanagedPackagesCmd installation cfg.uninstallUnmanagedPackages}

  # Configure remotes
  ${mkFlatpakAddRemoteCmd installation cfg.remotes}

  # Uninstall packages that have been removed from services.flatpak.packages
  # since the previous activation.
  ${flatpakUninstallCmd installation {}}

  # Install packages
  ${mkFlatpakInstallCmd installation updateApplications cfg.packages}

  # Save state
  ln -sf ${stateFile} ${statePath}
''

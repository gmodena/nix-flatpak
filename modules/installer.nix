{ cfg, pkgs, lib, installation ? "system", ... }:

let
  gcroots =
    if (installation == "system")
    then "/nix/var/nix/gcroots/"
    else "\${XDG_STATE_HOME:-$HOME/.local/state}/home-manager/gcroots";
  stateFile = pkgs.writeText "flatpak-state.json" (builtins.toJSON {
    packages = map (builtins.getAttr "appId") cfg.packages;
    overrides = cfg.overrides;
  });
  statePath = "${gcroots}/${stateFile.name}";

  updateApplications = cfg.update.onActivation || cfg.update.auto.enable;
  flatpakUninstallCmd = installation: {}: ''
    # Uninstall all packages that are present in the old state but not the new one.
    ${pkgs.jq}/bin/jq -r -n \
      --argjson old "$OLD_STATE" \
      --argjson new "$NEW_STATE" \
      '($old.packages - $new.packages)[]' \
      | while read -r APP_ID; do
          ${pkgs.flatpak}/bin/flatpak uninstall --${installation} -y $APP_ID
        done
  '';

  overridesDir =
    if (installation == "system")
    then "/var/lib/flatpak/overrides"
    else "\${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/overrides";
  flatpakOverridesCmd = installation: {}: ''
    # Update overrides that are managed by this module (both old and new)
    ${pkgs.jq}/bin/jq -r -n \
      --argjson old "$OLD_STATE" \
      --argjson new "$NEW_STATE" \
      '$new.overrides + $old.overrides | keys[]' \
      | while read -r APP_ID; do
          OVERRIDES_PATH=${overridesDir}/$APP_ID
          
          # Transform the INI-like Flatpak overrides file into a workable JSON
          if [[ -f $OVERRIDES_PATH ]]; then
            ACTIVE=$(cat $OVERRIDES_PATH \
              | ${pkgs.jc}/bin/jc --ini \
              | ${pkgs.jq}/bin/jq 'map_values(map_values(split(";") | select(. != []) // ""))')
          else
            ACTIVE={}
          fi

          # Generate and save the updated overrides file
          ${pkgs.jq}/bin/jq -r -n \
            --arg app_id "$APP_ID" \
            --argjson active "$ACTIVE" \
            --argjson old_state "$OLD_STATE" \
            --argjson new_state "$NEW_STATE" \
            --from-file ${./overrides.jq} \
            >$OVERRIDES_PATH
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

  # Configure remotes
  ${mkFlatpakAddRemoteCmd installation cfg.remotes}

  # Uninstall packages that have been removed from services.flatpak.packages
  # since the previous activation.
  ${flatpakUninstallCmd installation {}}

  # Install packages
  ${mkFlatpakInstallCmd installation updateApplications cfg.packages}

  # Configure overrides
  ${flatpakOverridesCmd installation {}}

  # Save state
  ln -sf ${stateFile} ${statePath}
''

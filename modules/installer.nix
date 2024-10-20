{ cfg, pkgs, lib, installation ? "system", ... }:

let
  utils = import ./ref.nix { inherit lib; };

  flatpakrefCache = builtins.foldl'
    (acc: package:
      acc // utils.flatpakrefToAttrSet package acc
    )
    { }
    (builtins.filter (package: utils.isFlatpakref package) cfg.packages);

  # Get the appId from the flatpakref file or the flatpakref URL to pass to flatpak commands.
  # As of 2024-10 Flatpak will fail to reinstall from flatpakref URL (https://github.com/flatpak/flatpak/issues/5460).
  # This function will return the appId if the package is already installed, otherwise it will return the flatpakref URL.
  getAppIdOrRef = flatpakrefUrl: installation:
    let
      appId = flatpakrefCache.${(utils.sanitizeUrl flatpakrefUrl)}.Name;
    in
    ''
      $(if ${pkgs.flatpak}/bin/flatpak --${installation} list --app --columns=application | ${pkgs.gnugrep}/bin/grep -q ${appId}; then
          echo "${appId}"
      else
          echo "--from ${flatpakrefUrl}"
      fi)
    '';

  # Put the state file in the `gcroots` folder of the respective installation,
  # which prevents it from being garbage collected. This could probably be
  # improved in the future if there are better conventions for how this should
  # be handled. Right now it introduces a small issue of the state file derivation
  # not being garbage collected even when this module is removed. You can find
  # more details on this design drawback in PR#23
  # State is represented by a JSON object with keys `packages`, `overrides` and `remotes`.
  # Example `flatpak-state.json`:
  # {
  #   "packages": ["org.gnome.Epiphany", "org.gnome.Epiphany.Devel"],
  #   "overrides": {
  #     "org.gnome.Epiphany": {
  #       "command": "env MOZ_ENABLE_WAYLAND=1 /run/current-system/sw/bin/epiphany",
  #       "env": "MOZ_ENABLE_WAYLAND=1"
  #     }
  #   },
  #   "remotes": ["flathub", "gnome-nightly"]
  # }
  gcroots =
    if (installation == "system")
    then "/nix/var/nix/gcroots/"
    else "\${XDG_STATE_HOME:-$HOME/.local/state}/home-manager/gcroots";

  stateFile = pkgs.writeText "flatpak-state.json" (builtins.toJSON {
    packages = (map
      (package:
        if utils.isFlatpakref package
        then flatpakrefCache.${(utils.sanitizeUrl package.flatpakref)}.Name # application id from flatpakref
        else package.appId
      )
      cfg.packages);
    overrides = cfg.overrides;
    # Iterate over remotes and handle remotes installed from flatpakref URLs
    remotes =
      # Existing remotes (not from flatpakref)
      (map (builtins.getAttr "name") cfg.remotes) ++
      # Add remotes extracted from flatpakref URLs in packages
      map
        (package:
          utils.getRemoteNameFromFlatpakref package.origin flatpakrefCache.${(utils.sanitizeUrl package.flatpakref)})
        (builtins.filter (package: utils.isFlatpakref package) cfg.packages);
  });

  statePath = "${gcroots}/${stateFile.name}";

  updateApplications = cfg.update.onActivation || cfg.update.auto.enable;

  # This script is used to manage the lifecyle of all flatpaks (remotes, packages)
  # installed on the system.
  # handeUnmanagedStateCmd is used to handle the case where the user wants nix-flatpak to manage
  # the state of the system, and uninstall any packages or remotes that are not declared in its config.
  handleUnmanagedStateCmd = installation: uninstallUnmanagedState:
    lib.optionalString uninstallUnmanagedState ''
      # Add all installed Flatpak packages to the old state, so only the managed ones (new state) will be kept
      INSTALLED_PACKAGES=$(${pkgs.flatpak}/bin/flatpak --${installation} list --app --columns=application)
      OLD_STATE=$(${pkgs.jq}/bin/jq -r -n \
        --argjson old "$OLD_STATE" \
        --arg installed_packages "$INSTALLED_PACKAGES" \
        '$old + { "packages" : $installed_packages | split("\n") }')

      # Add all configured remote to the old state, so that only managed ones will be kept across generations.
      MANAGED_REMOTES=$(${pkgs.flatpak}/bin/flatpak --${installation} remotes --columns=name)

      OLD_STATE=$(${pkgs.jq}/bin/jq -r -n \
        --argjson old "$OLD_STATE" \
        --arg managed_remotes "$MANAGED_REMOTES" \
        '$old + { "remotes": $managed_remotes | split("\n") }')

    '';

  flatpakUninstallCmd = installation: {}: ''
    # Uninstall all packages that are present in the old state but not the new one
    # $OLD_STATE and $NEW_STATE are globals, declared in the output of pkgs.writeShellScript.
    ${pkgs.jq}/bin/jq -r -n \
      --argjson old "$OLD_STATE" \
      --argjson new "$NEW_STATE" \
      '(($old.packages // []) - ($new.packages // []))[]' \
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
    ${pkgs.coreutils}/bin/mkdir -p ${overridesDir}
    ${pkgs.jq}/bin/jq -r -n \
      --argjson old "$OLD_STATE" \
      --argjson new "$NEW_STATE" \
      '$new.overrides + $old.overrides | keys[]' \
      | while read -r APP_ID; do
          OVERRIDES_PATH=${overridesDir}/$APP_ID

          # Transform the INI-like Flatpak overrides file into a workable JSON
          if [[ -f $OVERRIDES_PATH ]]; then
            ACTIVE=$(${pkgs.coreutils}/bin/cat $OVERRIDES_PATH \
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

  flatpakCmdBuilder = installation: action: args:
    "${pkgs.flatpak}/bin/flatpak --${installation} --noninteractive ${args} ${action} ";

  installCmdBuilder = installation: update: appId: flatpakref: origin:
    flatpakCmdBuilder installation " install "
      (if update then " --or-update " else " ") +
    (if utils.isFlatpakref { flatpakref = flatpakref; }
    then getAppIdOrRef flatpakref installation # If the appId is a flatpakref URL, get the appId from the flatpakref file
    else " ${origin} ${appId} ");

  updateCmdBuilder = installation: commit: appId:
    flatpakCmdBuilder installation "update"
      "--no-auto-pin --commit=\"${commit}\" ${appId}";

  flatpakInstallCmd = installation: update: { appId, origin ? "flathub", commit ? null, flatpakref ? null, ... }:
    let
      installCmd = installCmdBuilder installation update appId flatpakref origin;

      # pin the commit if it is provided
      pinCommitOrUpdate =
        if commit != null
        then updateCmdBuilder installation commit appId
        else "";
    in
    installCmd + "\n" + pinCommitOrUpdate;

  flatpakAddRemotesCmd = installation: { name, location, args ? null, ... }: ''
    ${pkgs.flatpak}/bin/flatpak remote-add --${installation} --if-not-exists ${if args == null then "" else args} ${name} ${location}
  '';
  flatpakAddRemote = installation: remotes: map (flatpakAddRemotesCmd installation) remotes;

  flatpakDeleteRemotesCmd = installation: {}: ''
    # Delete all remotes that are present in the old state but not the new one
    # $OLD_STATE and $NEW_STATE are globals, declared in the output of pkgs.writeShellScript.
    ${pkgs.jq}/bin/jq -r -n \
      --argjson old "$OLD_STATE" \
      --argjson new "$NEW_STATE" \
       '(($old.remotes // []) - ($new.remotes // []))[]' \
      | while read -r REMOTE_NAME; do
          ${pkgs.flatpak}/bin/flatpak remote-delete --${installation} $REMOTE_NAME
      done
  '';


  flatpakInstall = installation: update: packages: map (flatpakInstallCmd installation update) packages;

  mkFlatpakInstallCmd = installation: update: packages: builtins.foldl' (x: y: x + y) '''' (flatpakInstall installation update packages);
  mkFlatpakAddRemotesCmd = installation: remotes: builtins.foldl' (x: y: x + y) '''' (flatpakAddRemote installation remotes);
in
pkgs.writeShellScript "flatpak-managed-install" ''
  # This script is triggered at build time by a transient systemd unit.
  set -eu

  # Setup state variables for packages and remotes
  NEW_STATE=$(${pkgs.coreutils}/bin/cat ${stateFile})
  if [[ -f ${statePath} ]]; then
    OLD_STATE=$(${pkgs.coreutils}/bin/cat ${statePath})
  else
    OLD_STATE={}
  fi

  # Handle unmanaged packages and remotes.
  ${handleUnmanagedStateCmd installation cfg.uninstallUnmanaged}

  # Configure remotes
  ${mkFlatpakAddRemotesCmd installation cfg.remotes}

  # Uninstall packages that have been removed from services.flatpak.packages
  # since the previous activation.
  ${flatpakUninstallCmd installation {}}

  # Uninstall remotes that have been removed from services.flatpak.packages
  # since the previous activation.
  ${flatpakDeleteRemotesCmd installation {}}

  # Install packages
  ${mkFlatpakInstallCmd installation updateApplications cfg.packages}

  # Configure overrides
  ${flatpakOverridesCmd installation {}}

  # Save state
  ${pkgs.coreutils}/bin/ln -sf ${stateFile} ${statePath}
''

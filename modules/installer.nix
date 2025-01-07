{ cfg, pkgs, lib, installation ? "system", ... }:

let
  utils = import ./ref.nix { inherit lib; };
  remotes = import ./remotes.nix { inherit pkgs; };
  state = import ./state.nix { inherit pkgs; };

  flatpakrefCache = builtins.foldl'
    (acc: package:
      acc // utils.flatpakrefToAttrSet package acc
    )
    { }
    (builtins.filter (package: utils.isFlatpakref package) cfg.packages);

  # Get the appId and origin from a flatpakref file or URL to pass to flatpak commands.
  # As of 2024-10 Flatpak will fail to reinstall from flatpakref URL (https://github.com/flatpak/flatpak/issues/5460).
  # This function will return the appId if the package is already installed, otherwise it will return the flatpakref URL.
  installOrUpdateFromFlatpakref = flatpakrefUrl: installation:
    let
      appId = flatpakrefCache.${(utils.sanitizeUrl flatpakrefUrl)}.Name;
      origin = utils.getRemoteNameFromFlatpakref null flatpakrefCache.${(utils.sanitizeUrl flatpakrefUrl)};
    in
    ''
      $(if ${pkgs.flatpak}/bin/flatpak --${installation} list --app --columns=application | ${pkgs.gnugrep}/bin/grep -q ${appId}; then
          echo "${origin} ${appId}"
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
      (map (builtins.getAttr "name") cfg.remotes)
      ++
      # Add remotes extracted from flatpakref URLs in packages.
      # flatpakref remote names will override any origin set in the package.
      (builtins.filter (remote: !builtins.isNull remote)
        (map
          (package:
            utils.getRemoteNameFromFlatpakref null flatpakrefCache.${(utils.sanitizeUrl package.flatpakref)})
          (builtins.filter (package: utils.isFlatpakref package) cfg.packages)));
  });

  statePath = "${gcroots}/${stateFile.name}";

  # cache the old state. We need this to manipulate the state from nix expression.
  stateData = state.readState stateFile;

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
        # Guard against cases where a user removes an application both manually and through
        # configuration between activations. This code path triggers when uninstallUnmanaged=false
        # and nix-flatpak fails to clean up inconsistencies before reaching the uninstall phase.
        if ${pkgs.flatpak}/bin/flatpak --${installation} list --app --columns=application | ${pkgs.gnugrep}/bin/grep -q "^$APP_ID$"; then
          ${pkgs.flatpak}/bin/flatpak uninstall --${installation} -y $APP_ID
        else
          echo "WARNING: failed to uninstall '$APP_ID'. '$APP_ID' found in OLD_STATE, but not in '${installation}' installation. nix-flatpak state might be inconsistent."
        fi
    done
  '';

  flatpakUninstallUnusedCmd = installation: ''
    ${pkgs.flatpak}/bin/flatpak --${installation} uninstall --unused --noninteractive
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

  # TODO
  # - don't attempt an installation if appId is present in OLD_STATE
  installCmdBuilder = installation: update: appId: flatpakref: origin:
    flatpakCmdBuilder installation " install "
      (if update then " --or-update " else " ") +
    (if utils.isFlatpakref { flatpakref = flatpakref; }
    then installOrUpdateFromFlatpakref flatpakref installation # If the appId is a flatpakref URL, extract the appId and origin from the flatpakref.
    else " ${origin} ${appId} ");

  updateCmdBuilder = installation: commit: appId:
    flatpakCmdBuilder installation "update"
      "--no-auto-pin --commit=\"${commit}\" ${appId}";

  # Generates a shell command to install or update a Flatpak application based on 
  # various conditions. This command will either perform a new installation, update
  # to a specific commit, or skip if the application is already installed.
  #
  # Example:
  #   flatpakInstallCmd "user" false {
  #     appId = "local.test.App";
  #     commit = "abc123";
  #   }
  #
  # Arguments:
  #   installation    The Flatpak installation type (e.g., 'system' or 'user')
  #   update         Boolean flag to force update of existing installations
  #   appId          The Flatpak application ID to install
  #   origin         (optional) The Flatpak repository origin (default: "flathub")
  #   commit         (optional) Specific commit hash to pin the installation to
  #   flatpakref     (optional) Path to a .flatpakref file
  #
  # This function relies on state.shouldExecFlatpakInstall to determine if
  # installation is needed for the given parameters.
  flatpakInstallCmd = installation: update: { appId, origin ? "flathub", commit ? null, flatpakref ? null, ... }:
    let
      # Install if:
      # - update flag is true OR
      # - app is not installed OR
      # - commit is specified and doesn't match current
      shouldInstall = state.shouldExecFlatpakInstall stateData installation update appId commit;

      installCmd =
        if shouldInstall
        then
        # pin the commit if it is provided
          let
            pinCommitOrUpdate =
              if commit != null
              then updateCmdBuilder installation commit appId
              else "";
          in
          # To install at a specific commit hash we need to first install the appId,
            # then update to the pinned commit id.
          ''
            ${installCmdBuilder installation update appId flatpakref origin}
            ${pinCommitOrUpdate}
          ''
        else
          ''
            # ${appId} is already installed. Skipping.
          '';
    in
    installCmd;

  flatpakInstall = installation: update: packages: map (flatpakInstallCmd installation update) packages;

  mkFlatpakInstallCmd = installation: update: packages: builtins.foldl' (x: y: x + y) '''' (flatpakInstall installation update packages);

  flatpakDeleteRemotesCmd = remotes.flatpakDeleteRemotesCmd;
  mkFlatpakAddRemotesCmd = remotes.mkFlatpakAddRemotesCmd;
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
  ${flatpakDeleteRemotesCmd installation cfg.uninstallUnmanaged {}}  

  # Install packages
  ${mkFlatpakInstallCmd installation updateApplications cfg.packages}

  # Configure overrides
  ${flatpakOverridesCmd installation {}}

  # Clean up installation
  ${if cfg.uninstallUnused 
    then flatpakUninstallUnusedCmd installation
    else "# services.flatpak.uninstallUnused is not enabled "}  

  # Save state
  ${pkgs.coreutils}/bin/ln -sf ${stateFile} ${statePath}
''

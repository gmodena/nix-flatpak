{ cfg, pkgs, lib, installation ? "system", executionContext ? "service-start", ... }:

let
  utils = import ./ref.nix { inherit lib; };
  remotes = import ./remotes.nix { inherit pkgs; };

  flatpakrefCache = builtins.foldl'
    (acc: package:
      acc // utils.flatpakrefToAttrSet package acc
    )
    { }
    (builtins.filter (package: utils.isFlatpakref package) cfg.packages);

  formatVersion = "1.0.0";
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
    version = "v${formatVersion}";
    packages = map
      (package:
        let
          appId =
            if utils.isFlatpakref package
            then flatpakrefCache.${(utils.sanitizeUrl package.flatpakref)}.Name
            else package.appId;
        in
        {
          appId = appId;
          origin = package.origin or null;
          flatpakref = package.flatpakref or null;
          commit = package.commit or null;
        })
      cfg.packages;
    overrides = cfg.overrides;
    # Iterate over remotes and handle remotes installed from flatpakref URLs
    remotes =
      # Existing remotes (not from flatpakref)
      (map
        (remote:
          let name = remote.name;
          in { name = name; }
        )
        cfg.remotes)
      ++
      # Add remotes extracted from flatpakref URLs in packages.
      (map
        (remote:
          { name = remote; }
        )
        (builtins.filter (remote: !builtins.isNull remote)
          (map
            (package:
              utils.getRemoteNameFromFlatpakref null flatpakrefCache.${utils.sanitizeUrl package.flatpakref}
            )
            (builtins.filter (package: utils.isFlatpakref package) cfg.packages))));
  });

  statePath = "${gcroots}/${stateFile.name}";

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

  # This script is used to manage the lifecyle of all flatpaks (remotes, packages)
  # installed on the system.
  # handeUnmanagedStateCmd is used to handle the case where the user wants nix-flatpak to manage
  # the state of the system, and uninstall any packages or remotes that are not declared in its config.
  handleUnmanagedStateCmd = installation: uninstallUnmanagedState:
    lib.optionalString uninstallUnmanagedState ''
      # Add all installed Flatpak packages to the old state, so only the managed ones (new state) will be kept
      INSTALLED_PACKAGES=$(${pkgs.flatpak}/bin/flatpak --${installation} list --app --columns=application,origin,active)

      # Add all installed remotes to the old state, so that only managed (= declared in nix-flatpak's config)
      # ones will be kept across generations.
      INSTALLED_REMOTES=$(${pkgs.flatpak}/bin/flatpak --${installation} remotes --columns=name)
      
      # Add unmanaged packages and remotes to old state.
      OLD_STATE=$(${pkgs.jq}/bin/jq -r -n \
        --argjson old "$OLD_STATE" \
        --arg installed_packages "$INSTALLED_PACKAGES" \
        --arg installed_remotes "$INSTALLED_REMOTES" \
        --from-file ${./state/parse_statefile.jq})
    '';

  flatpakUninstallCmd = installation: {}: ''
    # Uninstall all packages that are present in the old state but not the new one
    # $OLD_STATE and $NEW_STATE are globals, declared in the output of pkgs.writeShellScript.
    ${pkgs.jq}/bin/jq -r -n --argjson old "$OLD_STATE" --argjson new "$NEW_STATE" --from-file ${./state/diff_packages.jq} | while read -r APP_ID; do
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
            --from-file ${./state/overrides.jq} \
            >$OVERRIDES_PATH
        done
  '';

  flatpakInstallCmd = installation: update: { appId, origin ? "flathub", commit ? null, flatpakref ? null, ... }:
    let
      cmdBuilder = installation: action: args:
        "${pkgs.flatpak}/bin/flatpak --${installation} --noninteractive ${action} ${args}";

      installCmdBuilder = installation: update: appId: flatpakref: origin:
        let
          updateFlag = if update then "--or-update" else "";
          sourceArgs =
            if utils.isFlatpakref { flatpakref = flatpakref; }
            then installOrUpdateFromFlatpakref flatpakref installation
            else "${origin} ${appId}";
        in
        cmdBuilder installation "install" "${updateFlag} ${sourceArgs}";

      resolvedAppId =
        if flatpakref != null
        then flatpakrefCache.${(utils.sanitizeUrl flatpakref)}.Name
        else appId;

      # flatpak install ...
      installCmd = installCmdBuilder installation update appId flatpakref origin;

      # flatpak update ...
      updatePinnedCmd =
        if commit != null
        then cmdBuilder installation "update" "--commit=\"${commit}\" ${resolvedAppId}"
        else "";

      installAndUpdatePinnedCmd = ''
        ${if installCmd != null then installCmd else ""}
        ${if updatePinnedCmd != null then updatePinnedCmd else ""}
      '';

      # Check if we need to execute flatpak install .... Which is when the state has changed:
      # 1. the script needs to run with --or-update (update.onActivation and/or update.auto are enabled).
      # 2. the application is not present in OLD_STATE and should be installed.
      # 3. the application is present in OLD_STATE, but is now pinned (explicitly)
      # at a different hash than the currently installed one.
      determineFlatpakStateChange =
        let
          safeCommit = if commit == null then "" else commit;
        in
        ''
          # Check if app exists in old state, handling both formats
          if $( ${pkgs.jq}/bin/jq -r -n --argjson old "$OLD_STATE" --arg appId "${resolvedAppId}" --from-file ${./state/app_exists.jq} | ${pkgs.gnugrep}/bin/grep -q true ); then
            # App exists in old state, check if commit changed
            if [[ -n "${safeCommit}" ]] && [[ "$( ${pkgs.flatpak}/bin/flatpak --${installation} info "${resolvedAppId}" --show-commit 2>/dev/null )" != "${safeCommit}" ]]; then
              ${updatePinnedCmd}
              : # No operation if no install command needs to run.
            fi
          else
            ${installAndUpdatePinnedCmd}
            : # No operation if no install command needs to run.
          fi
        '';
    in
    if update then installAndUpdatePinnedCmd else determineFlatpakStateChange;



  flatpakInstall = installation: update: packages: map (flatpakInstallCmd installation update) packages;


  flatpakDeleteRemotesCmd = remotes.flatpakDeleteRemotesCmd;

  updateTrigger =
    if executionContext == "service-start" then cfg.update.onActivation
    else if executionContext == "timer" then cfg.update.auto.enable
    else throw "flatpak-managed-install: invalid execution context `${executionContext}`" false;

  # Initializes state variables for managing Flatpak packages and remotes.
  # NEW_STATE is set to the content of `stateFile`. If `statePath` exists,
  # OLD_STATE is set to its content; otherwise, OLD_STATE is an empty dictionary.
  #
  # Inputs:
  # - stateFile: Path to the file containing the desired state.
  # - statePath: Path to the file representing the current state.
  # - pkgs.coreutils: Used for accessing the `cat` utility.
  mkLoadStateCmd = ''
      # Setup state variables for packages and remotes
    NEW_STATE=$(${pkgs.coreutils}/bin/cat ${stateFile})
    if [[ -f ${statePath} ]]; then
        OLD_STATE=$(${pkgs.coreutils}/bin/cat ${statePath})
    else
        OLD_STATE={}
    fi
  '';

  # Generates a command to install Flatpak packages defined in `cfg.packages`.
  # Combines installation commands using `flatpakInstall` for each package.
  # 
  # Inputs:
  # - installation: Installation context for Flatpak.
  # - updateTrigger: Triggers updates if enabled.
  # - cfg.packages: List of Flatpak packages to install.
  mkInstallCmd = builtins.foldl' (x: y: x + y) '''' (flatpakInstall installation updateTrigger cfg.packages);

  # Generates a command to uninstall Flatpak packages.
  # Uses `flatpakUninstallCmd` to produce the necessary command.
  # 
  # Inputs:
  # - installation: Installation context for Flatpak.
  mkUninstallCmd = flatpakUninstallCmd installation { };

  # Creates a command to manage unmanaged Flatpak states based on configuration.
  # Uses `handleUnmanagedStateCmd` with the current installation context and 
  # the `cfg.uninstallUnmanaged` option.
  # 
  # Inputs:
  # - installation: Installation context for Flatpak.
  # - cfg.uninstallUnmanaged: Boolean indicating whether to handle unmanaged packages.
  mkHandleUnmanagedStateCmd = handleUnmanagedStateCmd installation cfg.uninstallUnmanaged;

  # Produces a command to delete Flatpak remotes if `cfg.uninstallUnmanaged` is enabled.
  # Uses `flatpakDeleteRemotesCmd` to build the command.
  # 
  # Inputs:
  # - installation: Installation context for Flatpak.
  # - cfg.uninstallUnmanaged: Boolean to control removal of unmanaged remotes.
  mkDeleteRemotesCmd = flatpakDeleteRemotesCmd installation cfg.uninstallUnmanaged { };

  # Generates a command to set Flatpak overrides based on the current installation context.
  # Uses `flatpakOverridesCmd` to build the command.
  # 
  # Inputs:
  # - installation: Installation context for Flatpak.
  mkOverridesCmd = flatpakOverridesCmd installation { };

  # Generates a command to uninstall unused Flatpak packages if `cfg.uninstallUnused` is enabled.
  # Otherwise, outputs a comment indicating the feature is not enabled.
  # 
  # Inputs:
  # - installation: Installation context for Flatpak.
  # - cfg.uninstallUnused: Boolean indicating whether to uninstall unused packages.
  mkUninstallUnusedCmd =
    if cfg.uninstallUnused
    then flatpakUninstallUnusedCmd installation
    else "# services.flatpak.uninstallUnused is not enabled ";

  # Links the current state file (`stateFile`) to the state path (`statePath`).
  # This ensures that the current state is saved persistently.
  # 
  # Inputs:
  # - stateFile: Path to the current state file.
  # - statePath: Path to save the state file.
  # - pkgs.coreutils: Used for accessing the `ln` utility.
  mkSaveStateCmd = '' 
    ${pkgs.coreutils}/bin/ln -sf ${stateFile} ${statePath}
  '';

  # Generates a command to add Flatpak remotes based on the provided configuration and installation context.
  # Delegates to `remotes.mkFlatpakAddRemotesCmd` to construct the necessary commands.
  # 
  # Inputs:
  # - installation: Installation context for Flatpak.
  # - cfg.remotes: Configuration specifying the remotes to be added.
  # - remotes: Module providing the `mkFlatpakAddRemotesCmd` function.
  # 
  # Output:
  # - Command to add the specified Flatpak remotes.
  mkAddRemotesCmd = remotes.mkFlatpakAddRemotesCmd installation cfg.remotes;

in
{
  inherit mkLoadStateCmd mkInstallCmd mkUninstallCmd mkHandleUnmanagedStateCmd mkAddRemotesCmd mkDeleteRemotesCmd mkOverridesCmd mkUninstallUnusedCmd mkSaveStateCmd;
}

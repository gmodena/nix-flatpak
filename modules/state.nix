# Helper functions for managing nix-flatpak state.
# Historically, nix-flatpak relied on `jq` to read, parse, and process
# state files. Over time, the codebase is being refactored to
# favor using Nix expressions instead.
{ pkgs, ... }:
let

  # Reads and parses a JSON state file.
  # Takes a file path, and converts it from JSON format
  # to a Nix-compatible data structure using built-in functions.
  #
  # Parameters:
  #   stateFile: file path
  #
  # Returns
  # attrset: nix representation of the nix-flatpak state
  #
  readState = stateFile:
    builtins.fromJSON (builtins.readFile (builtins.toString stateFile));


  # TODO: Checks if a Flatpak app's current commit matches an expected commit hash
  #
  # Parameters:
  # installation: type of Flatpak installation (user, system)
  # appId:        flatpak application id (e.g., org.mozilla.firefox)
  # commit:       expected commit hash to check against, or null to skip check
  #
  # Returns:
  # boolean: True if either:
  #   - commit parameter is null (skip check)
  #   - current installed commit matches expected commit
  #   False otherwise
  #
  checkCommitMatch = installation: appId: commit:
    # we don't store commit into in flatpak-state.json,
    # and checks during Nix evaluation is tricky.
    # If a `commit` is provided, assume it does not match
    # the currently installed one, and force an update. In practice,
    # the application won't be re-donwloaded, but its ref will be looked up
    # in the remote.
    # FIXME: https://github.com/gmodena/nix-flatpak/issues/85
    commit == null || false;

  # Determines if flatpak install command should be executed based on system state
  #
  # Parameters:
  # installation: Path to Flatpak installation
  # update:       Boolean flag to force update
  # appId:        Flatpak application ID 
  # commit:       Expected commit hash or null
  #
  # Returns:
  # boolean: True if any of:
  #   - update flag is true
  #   - app is not installed
  #   - commit is specified and doesn't match current
  #
  shouldExecFlatpakInstall = stateData: installation: update: appId: commit:
    let
      # Currently (2024-12) we don't store the commit hash pin in nix-flatpak state.
      isInstalled = builtins.elem appId stateData."packages";

      # Verify commit hash matches if app is installed and a commit is pinned.
      commitMatches =
        if isInstalled
        then checkCommitMatch installation appId commit
        else false;

      # Run `flatpak install` if:
      # - update flag is true OR
      # - app is not installed OR
      # - commit is specified and doesn't match current
      shouldInstall = update || !isInstalled || (commit != null && !commitMatches);
    in
    shouldInstall;

in
{
  inherit readState shouldExecFlatpakInstall;
}

{ pkgs }:

let
  flatpakAddRemotesCmd = installation: { name, location, gpg-import ? null, args ? null, ... }:
    let
      gpg-import-flag = ''${if gpg-import == null then "" else "--gpg-import=${gpg-import}" }'';
      args-flag = ''${if args == null then "" else args}'';
    in
    ''
      if ! ${pkgs.flatpak}/bin/flatpak remotes --${installation} --columns=name | ${pkgs.gnugrep}/bin/grep -q '^${name}$'; then
        ${pkgs.flatpak}/bin/flatpak remote-add --${installation} --if-not-exists ${args-flag} ${gpg-import-flag} ${name} ${location}
      fi
    '';

  flatpakAddRemote = installation: remotes: map (flatpakAddRemotesCmd installation) remotes;

  flatpakDeleteRemotesCmd = installation: uninstallUnmanaged: {}: ''
    # Delete all remotes that are present in the old state but not the new one
    # $OLD_STATE and $NEW_STATE are globals, declared in the output of pkgs.writeShellScript.
    # If uninstallUnmanagedState is true, then the remotes will be deleted forcefully.
    #
    # Test if the remote exists before deleting it. This guards against two potential issues:
    # 1. A Flatpakref might install non-enumerable remotes that are automatically deleted
    #    when the application is uninstalled, so attempting to delete them without checking
    #    could cause errors.
    # 2. Users might manually delete apps/remotes, which could impact nix-flatpak state;
    #    checking prevents errors if the remote has already been removed.
    ${pkgs.jq}/bin/jq -r -n \
      --argjson old "$OLD_STATE" \
      --argjson new "$NEW_STATE" \
       '(($old.remotes // []) - ($new.remotes // [])).[].name' \
      | while read -r REMOTE_NAME; do
          if ${pkgs.flatpak}/bin/flatpak --${installation} remotes --columns=name | grep -q "^$REMOTE_NAME$"; then
            ${pkgs.flatpak}/bin/flatpak remote-delete ${if uninstallUnmanaged then " --force " else " " } --${installation} $REMOTE_NAME
          else
            echo "Remote '$REMOTE_NAME' not found in flatpak remotes"
          fi
      done
  '';

  mkFlatpakAddRemotesCmd = installation: remotes: builtins.foldl' (x: y: x + y) '''' (flatpakAddRemote installation remotes);
in
{
  inherit mkFlatpakAddRemotesCmd flatpakDeleteRemotesCmd;
}

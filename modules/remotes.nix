{ pkgs }:

let
  flatpakAddRemotesCmd = installation: { name, location, gpg-import ? null, args ? null, ... }:
    let
      gpg-import-flag = ''${if gpg-import == null then "" else "--gpg-import=${gpg-import}" }'';
      args-flag = ''${if args == null then "" else args}'';
    in
    ''
      ${pkgs.flatpak}/bin/flatpak remote-add --${installation} --if-not-exists ${args-flag} ${gpg-import-flag} ${name} ${location}
    '';

  flatpakAddRemote = installation: remotes: map (flatpakAddRemotesCmd installation) remotes;

  flatpakDeleteRemotesCmd = installation: uninstallUnmanaged: {}: ''
    # Delete all remotes that are present in the old state but not the new one
    # $OLD_STATE and $NEW_STATE are globals, declared in the output of pkgs.writeShellScript.
    # If uninstallUnmanagedState is true, then the remotes will be deleted forcefully.
    ${pkgs.jq}/bin/jq -r -n \
      --argjson old "$OLD_STATE" \
      --argjson new "$NEW_STATE" \
       '(($old.remotes // []) - ($new.remotes // []))[]' \
      | while read -r REMOTE_NAME; do
          ${pkgs.flatpak}/bin/flatpak remote-delete ${if uninstallUnmanaged then " --force " else " " } --${installation} $REMOTE_NAME

      done
  '';

  mkFlatpakAddRemotesCmd = installation: remotes: builtins.foldl' (x: y: x + y) '''' (flatpakAddRemote installation remotes);
in
{
  inherit mkFlatpakAddRemotesCmd flatpakDeleteRemotesCmd;
}

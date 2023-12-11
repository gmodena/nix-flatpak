{ cfg, pkgs, lib, installation ? "system", ... }:

let
  gcroots =
    if (installation == "system")
    then "/nix/var/nix/gcroots/"
    else "\${XDG_STATE_HOME:-$HOME/.local/state}/home-manager/gcroots";
  stateFile = pkgs.writeText "flatpak-state.json" (builtins.toJSON {
    packages = map (builtins.getAttr "appId") cfg.packages;
  });
  statePath = "${gcroots}/${stateFile.name}";

  updateApplications = cfg.update.onActivation || cfg.update.auto.enable;
  flatpakUninstallCmd = installation: {}: ''
    # Can't uninstall if we don't know the old state.
    if [[ -f ${statePath} ]]; then
      # Uninstall all packages that are present in the old state but not the new one.
      ${pkgs.jq}/bin/jq -r -n \
        --slurpfile old ${statePath} \
        --slurpfile new ${stateFile} \
        '($old[].packages - $new[].packages)[]' \
        | while read -r APP_ID; do
            ${pkgs.flatpak}/bin/flatpak uninstall --${installation} -y $APP_ID
          done
    fi
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

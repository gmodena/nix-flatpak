{ cfg, pkgs, lib, installation ? "system", ... }:

let
  updateApplications = cfg.update.onActivation || cfg.update.auto.enable;
  applicationsToKeep = lib.strings.concatStringsSep " " (map (builtins.getAttr "appId" ) cfg.packages);
  flatpakUninstallCmd = installation: {}: ''
        APPS_TO_KEEP=("${applicationsToKeep}")
        # Get a list of currently installed Flatpak application IDs
        INSTALLED_APPS=$(${pkgs.flatpak}/bin/flatpak  --${installation} list --app --columns=application | ${pkgs.gawk}/bin/awk '{print ''$1}')

        # Iterate through the installed apps and uninstall those not present in the to keep list
        for APP_ID in $INSTALLED_APPS; do
            if [[ ! " ''${APPS_TO_KEEP[@]} " =~ " ''${APP_ID} " ]]; then
                ${pkgs.flatpak}/bin/flatpak uninstall --${installation} -y ''$APP_ID
            fi
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

  # Configure remotes
  ${mkFlatpakAddRemoteCmd installation cfg.remotes}

  # Uninstall packages that have been removed from services.flatpak.packages
  # since the previous activation.
  ${flatpakUninstallCmd installation {}}

  # Install packages
  ${mkFlatpakInstallCmd installation updateApplications cfg.packages}
''

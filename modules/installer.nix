{ cfg, pkgs, installation ? "system", ... }:

let
  flatpakInstallCmd = installation: { appId, origin ? "flathub", commit ? null, ... }: ''
    ${pkgs.flatpak}/bin/flatpak --${installation} --noninteractive --no-auto-pin install ${origin} ${appId}
    ${if commit == null
        then '' ''
        else ''${pkgs.flatpak}/bin/flatpak --${installation} unpdate --commit="${commit}" ${origin} ${appId}
    ''}'';

  flatpakAddRemoteCmd = installation: { name, location, args ? null, ... }: ''
    ${pkgs.flatpak}/bin/flatpak remote-add --${installation} --if-not-exists ${if args == null then "" else args} ${name} ${location}
  '';
  flatpakAddRemote = installation: remotes: map (flatpakAddRemoteCmd installation) remotes;
  flatpakInstall = installation: packages: map (flatpakInstallCmd installation) packages;

  mkFlatpakInstallCmd = installation: packages: builtins.foldl' (x: y: x + y) '''' (flatpakInstall installation packages);
  mkFlatpakAddRemoteCmd = installation: remotes: builtins.foldl' (x: y: x + y) '''' (flatpakAddRemote installation remotes);
  mkFlatpakInstallScript = installation: pkgs.writeShellScript "flatpak-managed-install" ''
    # This script is triggered at build time by a transient systemd unit.
    set -eu

    # Configure remotes
    ${mkFlatpakAddRemoteCmd installation cfg.remotes}

    # Insall packages
    ${mkFlatpakInstallCmd installation cfg.packages}
  '';
in
pkgs.writeShellScript "flatpak-managed-install" ''
  # This script is triggered at build time by a transient systemd unit.
  set -eu

  # Configure remotes
  ${mkFlatpakAddRemoteCmd installation cfg.remotes}

  # Insall packages
  ${mkFlatpakInstallCmd installation cfg.packages}
''

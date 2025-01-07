# Generates the installer script.
# The script manages the update lifecycles for 
# `services.flatpak.update.onActivation` and `services.flatpak.update.auto.enable`,
# adapting its behavior based on whether it is invoked during service startup
# or by a system timer.
{ cfg, pkgs, lib, installation ? "system", executionContext ? "service-start", ... }:

let
  inherit (import ../flatpak/install.nix {
    inherit cfg pkgs lib installation executionContext;
  }) mkLoadStateCmd mkHandleUnmanagedStateCmd mkAddRemotesCmd mkUninstallCmd mkDeleteRemotesCmd mkInstallCmd mkOverridesCmd mkUninstallUnusedCmd mkSaveStateCmd;

in
pkgs.writeShellScript "flatpak-managed-install" ''

    # This script is triggered at build time by a transient systemd unit.
    set -eu
    ${mkLoadStateCmd}

    # Handle unmanaged packages and remotes.
    ${mkHandleUnmanagedStateCmd}

    # Configure remotes
    ${mkAddRemotesCmd}

    # Uninstall packages that have been removed from services.flatpak.packages
    # since the previous activation.
    ${mkUninstallCmd}

    # Uninstall remotes that have been removed from services.flatpak.packages
    # since the previous activation.
    ${mkDeleteRemotesCmd}  

    # Flatpak installation commands. The script manages the update lifecycles
    # for `services.flatpak.update.onActivation` and `services.flatpak.update.auto.enable`,
    # adapting its behaviorvbased on whether it is invoked during
    # service startup or by a system timer.
    ${mkInstallCmd}

    # Configure overrides
    ${mkOverridesCmd}

    # Clean up installation
    ${mkUninstallUnusedCmd}

    # Save state
    ${mkSaveStateCmd}
    ''

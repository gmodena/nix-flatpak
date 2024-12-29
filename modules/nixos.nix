{ config, lib, pkgs, ... }:
let
  cfg = lib.warnIf (! isNull config.services.flatpak.uninstallUnmanagedPackages)
    "uninstallUnmanagedPackages is deprecated since nix-flatpak 0.4.0 and will be removed in 1.0.0. Use uninstallUnmanaged instead."
    config.services.flatpak;
  installation = "system";
  exponentialBackoff = if config.services.flatpak.restartOnFailure.exponentialBackoff.enable then {
    RestartSteps = config.services.flatpak.restartOnFailure.exponentialBackoff.steps;
    RestartMaxDelaySec = config.services.flatpak.restartOnFailure.exponentialBackoff.maxDelay;
  } else {};
  restartOptions = if config.services.flatpak.restartOnFailure.enable then {
    Restart = "on-failure";
    RestartSec = config.services.flatpak.restartOnFailure.restartDelay;
    } // exponentialBackoff else {};
in
{
  options.services.flatpak = import ./options.nix { inherit config lib pkgs; };

  config = lib.mkIf config.services.flatpak.enable {
    systemd.services."flatpak-managed-install" = {
      wantedBy = [
        "default.target" # multi-user target with a GUI. For a desktop, this is typically going to be the graphical.target
      ];
      after = [
        "multi-user.target" # ensures that network & connectivity have been setup.
      ];
      serviceConfig = {
        Type = "oneshot"; # TODO: should this be an async startup, to avoid blocking on network at boot ?
        ExecStart = import ./installer.nix { inherit cfg pkgs lib installation; };
      } // restartOptions;
    };
    systemd.timers."flatpak-managed-install" = lib.mkIf config.services.flatpak.update.auto.enable {
      timerConfig = {
        Unit = "flatpak-managed-install";
        OnCalendar = config.services.flatpak.update.auto.onCalendar;
        Persistent = "true";
      };
      wantedBy = [ "timers.target" ];
    };
  };
}

{ lib, config }:
rec {
  mkExponentialBackoff = cfg:
    if cfg.restartOnFailure.exponentialBackoff.enable then {
      RestartSteps = cfg.restartOnFailure.exponentialBackoff.steps;
      RestartMaxDelaySec = cfg.restartOnFailure.exponentialBackoff.maxDelay;
    } else { };

  mkRestartOptions = cfg:
    if cfg.restartOnFailure.enable then {
      Restart = "on-failure";
      RestartSec = cfg.restartOnFailure.restartDelay;
    } // (mkExponentialBackoff cfg) else { };

  mkCommonServiceConfig = { cfg, pkgs, lib, installation, executionContext ? "service-start" }: {
    Type = "oneshot";
    ExecStart = import ./script/flatpak-managed-install.nix { inherit cfg pkgs lib installation executionContext; };
  };

  mkCommonTimerConfig = cfg: {
    Unit = "flatpak-managed-install";
    OnCalendar = cfg.update.auto.onCalendar;
    Persistent = "true";
  };

  warnDeprecated = cfg:
    lib.warnIf (! isNull cfg.uninstallUnmanagedPackages)
      "uninstallUnmanagedPackages is deprecated since nix-flatpak 0.4.0 and will be removed in 1.0.0. Use uninstallUnmanaged instead."
      cfg;
}

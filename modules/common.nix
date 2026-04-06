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
    Unit = "flatpak-managed-install-timer.service";
    OnCalendar = cfg.update.auto.onCalendar;
    Persistent = "true";
  };

  # Detect legacy overrides format (settings directly under `overrides` instead of `overrides.settings`).
  # Note: since the `overrides` option now uses `coercedTo`, freshly-evaluated NixOS/home-manager
  # configs will always arrive here in the new submodule shape. Coercion normalises the legacy format
  # before it reaches this function. This check therefore only fires when reading legacy JSON state
  # files that were written by an older version of nix-flatpak and have not yet been migrated.
  hasLegacyOverrides = cfg:
    let
      newFormatKeys = [ "settings" "files" "deleteOrphanedFiles" ];
      overrideKeys = builtins.attrNames (cfg.overrides or {});
      legacyKeys = builtins.filter (k: !(builtins.elem k newFormatKeys)) overrideKeys;
    in
    legacyKeys != [];

  warnDeprecated = cfg:
    lib.warnIf (! isNull cfg.uninstallUnmanagedPackages)
      "uninstallUnmanagedPackages is deprecated since nix-flatpak 0.4.0 and will be removed in 1.0.0. Use uninstallUnmanaged instead."
    (lib.warnIf (hasLegacyOverrides cfg)
      "Use 'services.flatpak.overrides.settings' instead of 'services.flatpak.overrides' for app overrides. Direct
      `overrides` configuration is deprecated and will be removed in future nix-flatpak versions."
      cfg);
}

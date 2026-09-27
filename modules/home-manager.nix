{ config, lib, pkgs, ... }@args:
let
  inherit (config.systemd.user) systemctlPath;
  helpers = import ./common.nix { inherit lib config; };
  cfg = helpers.warnDeprecated config.services.flatpak;
  installation = "user";
in
{
  options.services.flatpak = (import ./options.nix { inherit config lib pkgs; })
    // {
    enable = with lib; mkOption {
      type = types.bool;
      default = args.osConfig.services.flatpak.enable or false;
      description = "Whether to enable nix-flatpak declarative flatpak management in home-manager.";
    };
    setUserEnvironment = with lib; mkOption {
      type = types.bool;
      default = config.services.flatpak.enable;
      description = "Whether to add flatpak related user directories to user environment.";
    };
  };

  config = lib.mkIf config.services.flatpak.enable {
    systemd.user.services."flatpak-managed-install" = {
      Unit.After = [ "multi-user.target" ];
      Install.WantedBy = [ "default.target" ];
      Service = helpers.mkCommonServiceConfig
        {
          inherit cfg pkgs lib installation;
          executionContext = "service-start";
        } // helpers.mkRestartOptions cfg;
    };

    # Create a service that will only be started by a timer.
    # We need a separate service to provide a custom Enviroment
    # that installer used to determine if certain action (e.g. updates)
    # should be performed at activation or not.
    systemd.user.services."flatpak-managed-install-timer" = lib.mkIf config.services.flatpak.update.auto.enable {
      Service = helpers.mkCommonServiceConfig
        {
          inherit cfg pkgs lib installation;
          executionContext = "timer";
        } // helpers.mkRestartOptions cfg;
    };

    systemd.user.timers."flatpak-managed-install-timer" = lib.mkIf config.services.flatpak.update.auto.enable {
      Install.WantedBy = [ "timers.target" ];
      Timer = helpers.mkCommonTimerConfig cfg;
      Unit.Description = "flatpak update schedule";
    };

    home.activation = {
      flatpak-managed-install = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
        $DRY_RUN_CMD ${systemctlPath} is-system-running -q && \
          ${systemctlPath} --user start flatpak-managed-install.service || true
      '';
    };

    xdg.enable = true;

    xdg.systemDirs.data = lib.mkIf config.services.flatpak.setUserEnvironment ["${config.xdg.dataHome}/flatpak/exports/share"];
    home.sessionPath = lib.mkIf config.services.flatpak.setUserEnvironment ["${config.xdg.dataHome}/flatpak/exports/bin"];
  };
}

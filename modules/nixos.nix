{ config, lib, pkgs, ... }:
let
  helpers = import ./common.nix { inherit lib config; };
  cfg = helpers.warnDeprecated config.services.flatpak;
  installation = "system";
in
{
  options.services.flatpak = import ./options.nix { inherit config lib pkgs; };

  config = lib.mkIf config.services.flatpak.enable {
    systemd.services."flatpak-managed-install" = {
      wantedBy = [ "default.target" ];
      after = [ "multi-user.target" ];
      serviceConfig = helpers.mkCommonServiceConfig
        {
          inherit cfg pkgs lib installation;
          invokedFrom = "service-start";
        } // helpers.mkRestartOptions cfg;
    };

    # Create a service that will only be started by a timer.
    # We need a separate service to provide a custom Enviroment
    # that installer used to determine if certain action (e.g. updates)
    # should be performed at activation or not.
    systemd.services."flatpak-managed-install-timer" = lib.mkIf config.services.flatpak.update.auto.enable {
      serviceConfig = helpers.mkCommonServiceConfig
        {
          inherit cfg pkgs lib installation;
          invokedFrom = "timer";
        } // helpers.mkRestartOptions cfg;
    };

    systemd.timers."flatpak-managed-install-timer" = lib.mkIf config.services.flatpak.update.auto.enable {
      timerConfig = helpers.mkCommonTimerConfig cfg;
      wantedBy = [ "timers.target" ];
    };
  };
}

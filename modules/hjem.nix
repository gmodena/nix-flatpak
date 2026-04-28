{
  config,
  lib,
  pkgs,
  ...
}:
let
  helpers = import ./common.nix { inherit lib; };
  cfg = helpers.warnDeprecated config.services.flatpak;
  installation = "user";
in
{
  options.services.flatpak = (import ./options.nix { inherit config lib pkgs; }) // {
    enable = lib.mkEnableOption "nix-flatpak";
  };
  config = lib.mkIf cfg.enable {
    systemd = {
      services."flatpak-managed-install" = {
        after = [ "multi-user.target" ];
        wantedBy = [ "default.target" ];
        serviceConfig =
          helpers.mkCommonServiceConfig {
            inherit cfg pkgs lib installation ;
            executionContext = "service-start";
          }
          // helpers.mkRestartOptions cfg;
      };
      timers."flatpak-managed-install-timer" = lib.mkIf cfg.update.auto.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = helpers.mkCommonTimerConfig cfg;
      };
    };
  };
}

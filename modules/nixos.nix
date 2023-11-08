{ config, lib, pkgs, ... }:
let
  cfg = config.services.flatpak;
  installation = "system";
in
{
  options.services.flatpak = import ./default.nix { inherit cfg lib pkgs; };

  config = lib.mkIf config.services.flatpak.enable {
    systemd.services."flatpak-managed-install" = {
      wants = [
        "network-online.target"
      ];
      wantedBy = [
        "multi-user.target"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${import ./installer.nix {inherit cfg pkgs; installation = installation; }}";
      };
    };
    systemd.timers."flatpak-managed-install" = lib.mkIf config.services.flatpak.update.auto.enable {
      timerConfig = {
        Unit = "flatpak-managed-install";
        OnCalendar = "${config.services.flatpak.update.auto.onCalendar}";
        Persistent = "true";
      };
      wantedBy = [ "timers.target" ];
    };
  };
}

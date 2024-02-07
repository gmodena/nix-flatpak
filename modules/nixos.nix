{ config, lib, pkgs, ... }:
let
  cfg = config.services.flatpak;
  installation = "system";
in
{
  options.services.flatpak = import ./options.nix { inherit lib pkgs; };

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
        RemainAfterExit = "yes";
        ExecStart = import ./installer.nix { inherit cfg pkgs lib installation; };
      };
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

{ config, lib, pkgs, osConfig, ... }:
let
  cfg = config.services.flatpak;
  installation = "user";
in
{

  options.services.flatpak = import ./default.nix { inherit cfg lib pkgs; };

  config = lib.mkIf osConfig.services.flatpak.enable {
    systemd.user.services."flatpak-managed-install" = {
      Unit = {
        After = [
          "network.target"
        ];
      };
      Install = {
        WantedBy = [
          "default.target"
        ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${import ./installer.nix {inherit cfg pkgs lib; installation = installation; }}";
      };
    };

    systemd.user.timers."flatpak-managed-install" = lib.mkIf config.services.flatpak.update.auto.enable {
      Unit.Description = "flatpak update schedule";
      Timer = {
        Unit = "flatpak-managed-install";
        OnCalendar = "${config.services.flatpak.update.auto.onCalendar}";
        Persistent = "true";
      };
      Install.WantedBy = [ "timers.target" ];
    };

    home.activation = {
      start-service = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH=${lib.makeBinPath (with pkgs; [ systemd ])}:$PATH

        $DRY_RUN_CMD systemctl is-system-running -q && \
          systemctl --user start flatpak-managed-install.service || true
      '';
    };

    xdg.enable = true;
  };

}

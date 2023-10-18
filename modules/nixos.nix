{ config, lib, pkgs, ... }:
let
  cfg = config.services.flatpak;
  installation = "system";
in
{
  options.services.flatpak = import ./default.nix { inherit cfg lib pkgs; };

  config = lib.mkIf config.services.flatpak.enable {
    systemd.services."flatpak-managed" = {
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
  };
}

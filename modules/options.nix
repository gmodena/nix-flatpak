{ lib, ... }:
with lib;
let
  remoteOptions = _: {
    options = {
      name = mkOption {
        type = types.str;
        description = lib.mdDoc "The remote name";
        default = "flathub";
      };
      location = mkOption {
        type = types.str;
        description = lib.mdDoc "The remote location";
        default = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      };
      args = mkOption {
        type = types.nullOr types.str;
        description = "Extra arguments to pass to flatpak remote-add";
        example = [ "--verbose" ];
        default = null;
      };
    };
  };

  packageOptions = _: {
    options = {
      appId = mkOption {
        type = types.str;
        description = lib.mdDoc "The fully qualified id of the app to install.";
      };

      commit = mkOption {
        type = types.nullOr types.str;
        description = lib.mdDoc "Hash id of the app commit to install";
        default = null;
      };

      origin = mkOption {
        type = types.str;
        default = "flathub";
        description = lib.mdDoc "App repository origin (default: flathub)";
      };
    };
  };

  updateOptions = _: {
    options = {
      onActivation = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Whether to enable flatpak to upgrade applications during
          {command}`nixos` system activation. The default is `false`
          so that repeated invocations of {command}`nixos-rebuild switch` are idempotent.

          implementation: appends --or-update to each flatpak install command.
        '';
      };
      auto = mkOption {
        type = with types; submodule (_: {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = lib.mdDoc ''
                Whether to enable flatpak to upgrade applications during
                {command}`nixos` system activation, and scheudle periodic updates
                afterwards.

                implementation: registers a systemd realtime timer that fires with an OnCalendar policy.
                If a timer had expired while a machine was off/asleep, it will fire upon resume.
                See https://wiki.archlinux.org/title/systemd/Timers for details.
              '';
            };
            onCalendar = mkOption {
              type = types.str;
              default = "weekly";
              description = lib.mdDoc ''
                Frequency of periodic updates.
                See https://wiki.archlinux.org/title/systemd/Timers for details.
              '';
            };
          };
        });
        default = { enable = false; };
      };
    };
  };


in
{
  packages = mkOption {
    type = with types; listOf (coercedTo str (appId: { inherit appId; }) (submodule packageOptions));
    default = [ ];
    description = mkDoc ''
      Declares a list of applications to install.
    '';
    example = literalExpression ''
      [
          # declare applications to install using its fqdn
          "com.obsproject.Studio"
          # specify a remote.
          { appId = "com.brave.Browser"; origin = "flathub";  }
          # Pin the application to a specific commit.
          { appId = "im.riot.Riot"; commit = "bdcc7fff8359d927f25226eae8389210dba3789ca5d06042d6c9c133e6b1ceb1" }
      ];
    '';
  };
  remotes = mkOption {
    type = with types; listOf (coercedTo str (name: { inherit name location; }) (submodule remoteOptions));
    default = [{ name = "flathub"; location = "https://dl.flathub.org/repo/flathub.flatpakrepo"; }];
    description = mkDoc ''
      Declare a list of flatpak repositories.
    '';
    example = literalExpression ''
      # Flathub is the default initialized by this flake.
      [{ name = "flathub"; location = "https://dl.flathub.org/repo/flathub.flatpakrepo"; }]
    '';
  };

  update = mkOption {
    type = with types; submodule updateOptions;
    default = { onActivation = false; auto = { enable = false; onCalendar = "weekly"; }; };
    description = lib.mdDoc ''
      Whether to enable flatpak to upgrade applications during
      {command}`nixos` system activation. The default is `false`
      so that repeated invocations of {command}`nixos-rebuild switch` are idempotent.

      Applications pinned to a specific commit hash will not be updated.

      If {command}`auto.enable = true` a periodic update will be scheduled with (approximately)
      weekly recurrence.

      See https://wiki.archlinux.org/title/systemd/Timers for more information on systemd timers.
    '';
    example = literalExpression ''
      # Update applications at system activation. Afterwards schedule (approximately) weekly updates.
      update = {
        auto = {
            enable = true;
            onCalendar = "weekly";
        };
      };
    '';
  };

  uninstallUnmanagedPackages = mkOption {
    type = with types; bool;
    default = false;
    description = lib.mdDoc ''
      If enabled, uninstall packages not managed by this module on activation.
      I.e. if packages were installed via Flatpak directly instead of this module,
      they would get uninstalled on the next activation
    '';
  };
}

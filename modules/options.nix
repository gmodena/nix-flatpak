{ config, lib, ... }:
with lib;
let
  remoteOptions = _: {
    options = {
      name = mkOption {
        type = types.str;
        description = "The remote name. This name is what will be used when installing flatpak(s) from this repo.";
        default = "flathub";
      };
      location = mkOption {
        type = types.str;
        description = "The remote location. Must be a valid URL of a flatpak repo.";
        default = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      };
      gpg-import = mkOption {
        type = types.nullOr types.str;
        description = "Import GPG key from FILE";
        default = null;
      };
      args = mkOption {
        type = types.nullOr types.str;
        description = "Extra arguments to pass to flatpak remote-add.";
        example = [ "--verbose" ];
        default = null;
      };
    };
  };

  packageOptions = _: {
    options = {
      appId = mkOption {
        type = types.str;
        description = "The fully qualified id of the app to install.";
      };

      commit = mkOption {
        type = types.nullOr types.str;
        description = "Hash id of the app commit to install.";
        default = null;
      };

      origin = mkOption {
        type = types.str;
        default = "flathub";
        description = "App repository origin (default: flathub).";
      };

      flatpakref = mkOption {
        type = types.nullOr types.str;
        description = "The flakeref URI of the app to install. ";
        default = null;
      };
      sha256 = mkOption {
        type = types.nullOr types.str;
        description = "The sha256 hash of the URI to install. ";
        default = null;
      };

      bundle = mkOption {
        type = types.nullOr types.str;
        description = ''
          Path to a local Flatpak bundle to install. The file name should follow Flatpak's conventions:
          https://docs.flatpak.org/en/latest/conventions.html
        '';
        default = null;
      };
    };
  };

  restartOptions = _: {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether the flatpak-managed-install service should restart in case of failure.
        '';
      };
      restartDelay = mkOption {
        type = types.str;
        default = "60s";
        description = ''
          Delay (in a systemd timespan format) after which update or installation is going to be retried in case of failure.
        '';
      };
      exponentialBackoff = mkOption {
        description = ''
          Specification for the exponential backoff stategy to adopt in case of service failure.
        '';
        type = with types; submodule (_: {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Whether to enable exponential backoff in case of failure during installation or upgrade.
              '';
            };

            steps = mkOption {
              type = types.int;
              default = 10;
              description = ''
                How many steps will be needed to reach the maximum restart delay.
              '';
            };

            maxDelay = mkOption {
              type = types.str;
              default = "1h";
              description = ''
                Maximum delay (in as systemd timespan format) after which update or installation is going to be retried in case of failure.
              '';
            };
          };
        });
        default = { enable = false; steps = 10; maxDelay = "1h"; };
      };
    };
  };

  updateOptions = _: {
    options = {
      onActivation = mkOption {
        type = types.bool;
        default = false;
        description = ''
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
              description = ''
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
              description = ''
                Frequency of periodic updates.
                See https://wiki.archlinux.org/title/systemd/Timers for details.
              '';
            };
          };
        });
        default = { enable = false; };
        description = ''
          Value(s) in this Nix set are used to configure the behavior of the auto updater.
        '';
      };
    };
  };

  overridesOptions = _: {
    options = {
      settings = mkOption {
        type = with types; attrsOf (attrsOf (attrsOf (either str (listOf str))));
        default = { };
        description = ''
          Applies the provided attribute set into a Flatpak overrides file with the
          same structure, keeping externally applied changes.
        '';
        example = literalExpression ''
          {
            # Array entries will be merged with externally applied values
            "com.visualstudio.code".Context.sockets = ["wayland" "!x11" "!fallback-x11"];
            # String entries will override externally applied values
            global.Environment.LC_ALL = "C.UTF-8";
          };
        '';
      };

      files = mkOption {
        type = with types; listOf str;
        default = [ ];
        description = ''
          A list of paths to Flatpak overrides files.
          The files will be merged with the overrides attribute set.
          The files are expected to be in the same format as the overrides attribute set.
        '';
        example = literalExpression ''
          [
            "/path/to/overrides.d/com.visualstudio.code"
            "/path/to/overrides.d/org.gnome.Terminal"
          ];
        '';
      };
    };
  };
in
{
  packages = mkOption {
    type = with types; listOf (coercedTo str (appId: { inherit appId; }) (submodule packageOptions));
    default = [ ];
    description = ''
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
    description = ''
      Declare a list of flatpak repositories.
    '';
    example = literalExpression ''
      # Flathub is the default initialized by this flake.
      [{ name = "flathub"; location = "https://dl.flathub.org/repo/flathub.flatpakrepo"; }]
    '';
  };

  overrides = mkOption {
    #type = with types; coercedTo attrs (attrs: { inherit attrs; }) (submodule overridesOptions);
    # type = with types; attrsOf (coercedTo attrs (attrs: { inherit attrs; }) (submodule overridesOptions));
    default = { };
    description = ''
      Applies the provided attribute set into a Flatpak overrides file with the
      same structure, keeping externally applied changes.
    '';
    example = literalExpression ''
      {
        # Array entries will be merged with externally applied values
        "com.visualstudio.code".Context.sockets = ["wayland" "!x11" "!fallback-x11"];
        # String entries will override externally applied values
        global.Environment.LC_ALL = "C.UTF-8";
      };
    '';
  };

  update = mkOption {
    type = with types; submodule updateOptions;
    default = { onActivation = false; auto = { enable = false; onCalendar = "weekly"; }; };
    description = ''
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
    type = lib.types.nullOr (lib.types.bool);
    default = null;
    description = ''
      uninstallUnmanagedPackages is deprecated. Use uninstallUnmanaged instead.'';
  };

  uninstallUnmanaged = mkOption {
    type = with types; bool;
    default = (if isNull config.services.flatpak.uninstallUnmanagedPackages then false else
    config.services.flatpak.uninstallUnmanagedPackages) || false;
    description = ''
      If enabled, uninstall packages and delete remotes not managed by this module on activation.
      I.e. if packages were installed via Flatpak directly instead of this module,
      they would get uninstalled on the next activation. The same applies to remotes manually setup via `flatpak remote-add`
    '';
  };

  restartOnFailure = mkOption {
    type = with types; submodule restartOptions;
    default = { enable = true; restartDelay = "60s"; exponentialBackoff = { enable = false; steps = 10; maxDelay = "1h"; }; };
    description = ''
      If enabled, restart the flatpak-managed-install service in case of failure.
      It is possible to specify a restart delay and an exponential backoff strategy.
    '';
  };

  uninstallUnused = mkOption {
    type = with types; bool;
    default = config.services.flatpak.uninstallUnmanaged || false;
    description = ''
      If enabled, uninstalls unused packages and runtimes.
      Defaults to `config.services.flatpak.uninstallUnmanaged`, or `false`.
    '';

  };
}

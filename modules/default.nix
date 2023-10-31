{ cfg, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.flatpak;

  remoteOptions = { cfg, ... }: {
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

  packageOptions = { cfg, ... }: {
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

}

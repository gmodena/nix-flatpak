# Tests for legacy override format backward compatibility.
# Verifies that install.nix can be evaluated when using the legacy format
# where overrides is just an attrset of settings (without .files or .deleteOrphanedFiles).
{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  installation = "user";

  # Base config with proper package attributes
  baseConfig = {
    update = {
      onActivation = false;
      auto = { enable = false; };
    };
    remotes = [{ name = "some-remote"; location = "https://some.remote.tld/repo/test-remote.flatpakrepo"; }];
    packages = [{ appId = "SomeAppId"; origin = "some-remote"; bundle = null; sha256 = null; }];
    uninstallUnmanaged = false;
    uninstallUnused = false;
  };

  # Legacy format: overrides is just an attrset of app settings
  # (no .files, .settings, or .deleteOrphanedFiles attributes)
  cfgLegacyOverrides = baseConfig // {
    overrides = {
      "com.example.app" = {
        "Context" = { "shared" = "network"; };
      };
    };
  };

  # New format with only settings (no files or deleteOrphanedFiles)
  cfgNewFormatSettingsOnly = baseConfig // {
    overrides = {
      settings = {
        "com.example.app" = {
          "Context" = { "shared" = "network"; };
        };
      };
    };
  };

  # New format with files but no deleteOrphanedFiles
  cfgNewFormatWithFiles = baseConfig // {
    overrides = {
      settings = {
        "com.example.app" = {
          "Context" = { "shared" = "network"; };
        };
      };
      files = [ "/path/to/com.other.app" ];
    };
  };

  # Full new format
  cfgFullNewFormat = baseConfig // {
    overrides = {
      settings = {
        "com.example.app" = {
          "Context" = { "shared" = "network"; };
        };
      };
      files = [ "/path/to/com.other.app" ];
      deleteOrphanedFiles = true;
    };
  };

  # Empty overrides (common case)
  cfgEmptyOverrides = baseConfig // {
    overrides = { };
  };

  installLegacy = import ../../modules/flatpak/install.nix {
    cfg = cfgLegacyOverrides;
    inherit pkgs lib installation;
    executionContext = "service-start";
  };

  installNewSettingsOnly = import ../../modules/flatpak/install.nix {
    cfg = cfgNewFormatSettingsOnly;
    inherit pkgs lib installation;
    executionContext = "service-start";
  };

  installNewWithFiles = import ../../modules/flatpak/install.nix {
    cfg = cfgNewFormatWithFiles;
    inherit pkgs lib installation;
    executionContext = "service-start";
  };

  installFullNew = import ../../modules/flatpak/install.nix {
    cfg = cfgFullNewFormat;
    inherit pkgs lib installation;
    executionContext = "service-start";
  };

  installEmpty = import ../../modules/flatpak/install.nix {
    cfg = cfgEmptyOverrides;
    inherit pkgs lib installation;
    executionContext = "service-start";
  };
in
runTests {
  # Test that legacy format evaluates without error
  # Cechks that mkOverridesCmd can be generated (uses cfg.overrides.files and cfg.overrides.deleteOrphanedFiles)
  testLegacyOverridesEvaluates = {
    expr = builtins.isString installLegacy.mkOverridesCmd;
    expected = true;
  };

  # Test new format with only settings (no files/deleteOrphanedFiles) evaluates
  testNewFormatSettingsOnlyEvaluates = {
    expr = builtins.isString installNewSettingsOnly.mkOverridesCmd;
    expected = true;
  };

  # Test new format with files but no deleteOrphanedFiles evaluates
  testNewFormatWithFilesEvaluates = {
    expr = builtins.isString installNewWithFiles.mkOverridesCmd;
    expected = true;
  };

  # Test full new format evaluates
  testFullNewFormatEvaluates = {
    expr = builtins.isString installFullNew.mkOverridesCmd;
    expected = true;
  };

  # Test empty overrides evaluates
  testEmptyOverridesEvaluates = {
    expr = builtins.isString installEmpty.mkOverridesCmd;
    expected = true;
  };

  # Test that mkSaveStateCmd can be generated for legacy format
  testLegacyOverridesMkSaveStateCmdEvaluates = {
    expr = builtins.isString installLegacy.mkSaveStateCmd;
    expected = true;
  };

  # Test that mkSaveStateCmd can be generated for empty overrides
  testEmptyOverridesMkSaveStateCmdEvaluates = {
    expr = builtins.isString installEmpty.mkSaveStateCmd;
    expected = true;
  };

  # Test that mkInstallCmd can be generated for legacy format
  testLegacyOverridesMkInstallCmdEvaluates = {
    expr = builtins.isString installLegacy.mkInstallCmd;
    expected = true;
  };

  # Test that all commands can be generated for full new format
  testFullNewFormatAllCommandsEvaluate = {
    expr = builtins.all (x: builtins.isString x) [
      installFullNew.mkOverridesCmd
      installFullNew.mkSaveStateCmd
      installFullNew.mkInstallCmd
      installFullNew.mkLoadStateCmd
    ];
    expected = true;
  };
}

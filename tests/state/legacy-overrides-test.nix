# Tests for legacy override format backward compatibility.
# Verifies that install.nix can be evaluated when using the legacy format
# where overrides is just an attrset of settings (without .files or .pruneUnmanagedOverrides).
{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  installation = "user";

  baseConfig = {
    update = {
      onActivation = false;
      auto = {enable = false;};
    };
    remotes = [
      {
        name = "some-remote";
        location = "https://some.remote.tld/repo/test-remote.flatpakrepo";
      }
    ];
    packages = [
      {
        appId = "SomeAppId";
        origin = "some-remote";
        bundle = null;
        sha256 = null;
      }
    ];
    uninstallUnmanaged = false;
    uninstallUnused = false;
  };

  # Legacy format: overrides is just an attrset of app settings
  # (no .files, .settings, or .pruneUnmanagedOverrides attributes)
  cfgLegacyOverrides =
    baseConfig
    // {
      overrides = {
        "com.example.app" = {
          "Context" = {"shared" = "network";};
        };
      };
    };

  # New format with only settings (no files or pruneUnmanagedOverrides)
  cfgNewFormatSettingsOnly =
    baseConfig
    // {
      overrides = {
        settings = {
          "com.example.app" = {
            "Context" = {"shared" = "network";};
          };
        };
      };
    };

  # New format with files but no pruneUnmanagedOverrides
  cfgNewFormatWithFiles =
    baseConfig
    // {
      overrides = {
        settings = {
          "com.example.app" = {
            "Context" = {"shared" = "network";};
          };
        };
        files = [(toString ../fixtures/overrides/com.other.app)];
      };
    };

  # Full new format
  cfgFullNewFormat =
    baseConfig
    // {
      overrides = {
        settings = {
          "com.example.app" = {
            "Context" = {"shared" = "network";};
          };
        };
        files = [(toString ../fixtures/overrides/com.other.app)];
        pruneUnmanagedOverrides = true;
      };
    };

  # writeMode = "merge" explicit
  cfgWriteModeMerge =
    baseConfig
    // {
      overrides = {
        writeMode = "merge";
        settings = {"com.example.app" = {"Context" = {"shared" = "network";};};};
      };
    };

  # writeMode = "replace"
  cfgWriteModeReplace =
    baseConfig
    // {
      overrides = {
        writeMode = "replace";
        settings = {"com.example.app" = {"Context" = {"shared" = "network";};};};
        files = [(toString ../fixtures/overrides/com.other.app)];
      };
    };

  # Empty overrides (common case)
  cfgEmptyOverrides =
    baseConfig
    // {
      overrides = {};
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

  installWriteModeMerge = import ../../modules/flatpak/install.nix {
    cfg = cfgWriteModeMerge;
    inherit pkgs lib installation;
    executionContext = "service-start";
  };

  installWriteModeReplace = import ../../modules/flatpak/install.nix {
    cfg = cfgWriteModeReplace;
    inherit pkgs lib installation;
    executionContext = "service-start";
  };
in
  runTests {
    testLegacyOverridesEvaluates = {
      expr = builtins.isString installLegacy.mkOverridesCmd;
      expected = true;
    };

    testNewFormatSettingsOnlyEvaluates = {
      expr = builtins.isString installNewSettingsOnly.mkOverridesCmd;
      expected = true;
    };

    testNewFormatWithFilesEvaluates = {
      expr = builtins.isString installNewWithFiles.mkOverridesCmd;
      expected = true;
    };

    testFullNewFormatEvaluates = {
      expr = builtins.isString installFullNew.mkOverridesCmd;
      expected = true;
    };

    testEmptyOverridesEvaluates = {
      expr = builtins.isString installEmpty.mkOverridesCmd;
      expected = true;
    };

    testLegacyOverridesMkSaveStateCmdEvaluates = {
      expr = builtins.isString installLegacy.mkSaveStateCmd;
      expected = true;
    };

    testEmptyOverridesMkSaveStateCmdEvaluates = {
      expr = builtins.isString installEmpty.mkSaveStateCmd;
      expected = true;
    };

    testLegacyOverridesMkInstallCmdEvaluates = {
      expr = builtins.isString installLegacy.mkInstallCmd;
      expected = true;
    };

    testFullNewFormatAllCommandsEvaluate = {
      expr = builtins.all (x: builtins.isString x) [
        installFullNew.mkOverridesCmd
        installFullNew.mkSaveStateCmd
        installFullNew.mkInstallCmd
        installFullNew.mkLoadStateCmd
      ];
      expected = true;
    };

    testDuplicateBasenamesThrows = {
      expr = builtins.tryEval (
        (import ../../modules/flatpak/install.nix {
          cfg =
            baseConfig
            // {
              overrides = {
                files = [
                  "/path/a/com.example.app"
                  "/path/b/com.example.app"
                ];
              };
            };
          inherit pkgs lib installation;
          executionContext = "service-start";
        }).mkSaveStateCmd
      );
      expected = {
        success = false;
        value = false;
      };
    };

    testPathWithNewlineThrows = {
      expr = builtins.tryEval (
        (import ../../modules/flatpak/install.nix {
          cfg =
            baseConfig
            // {
              overrides = {
                files = ["/path/to/com.example\napp"];
              };
            };
          inherit pkgs lib installation;
          executionContext = "service-start";
        }).mkSaveStateCmd
      );
      expected = {
        success = false;
        value = false;
      };
    };

    testPathWithSingleQuoteThrows = {
      expr = builtins.tryEval (
        (import ../../modules/flatpak/install.nix {
          cfg =
            baseConfig
            // {
              overrides = {
                files = ["/path/to/com.example'app"];
              };
            };
          inherit pkgs lib installation;
          executionContext = "service-start";
        }).mkSaveStateCmd
      );
      expected = {
        success = false;
        value = false;
      };
    };

    testPathWithCarriageReturnThrows = {
      expr = builtins.tryEval (
        (import ../../modules/flatpak/install.nix {
          cfg =
            baseConfig
            // {
              overrides = {
                files = ["/path/to/com.example\rapp"];
              };
            };
          inherit pkgs lib installation;
          executionContext = "service-start";
        }).mkSaveStateCmd
      );
      expected = {
        success = false;
        value = false;
      };
    };

    testPathWithNullByteThrows = {
      expr = builtins.tryEval (
        (import ../../modules/flatpak/install.nix {
          cfg =
            baseConfig
            // {
              overrides = {
                files = ["/path/to/com.example\x00app"];
              };
            };
          inherit pkgs lib installation;
          executionContext = "service-start";
        }).mkSaveStateCmd
      );
      expected = {
        success = false;
        value = false;
      };
    };

    testWriteModeMergeEvaluates = {
      expr = builtins.isString installWriteModeMerge.mkOverridesCmd;
      expected = true;
    };

    testWriteModeReplaceEvaluates = {
      expr = builtins.isString installWriteModeReplace.mkOverridesCmd;
      expected = true;
    };

    testDefaultWriteModeIsMerge = {
      expr = lib.strings.hasInfix "cp --no-preserve" installNewSettingsOnly.mkOverridesCmd;
      expected = false;
    };

    testValidUniquePathsSucceed = {
      expr = builtins.isString (
        (import ../../modules/flatpak/install.nix {
          cfg =
            baseConfig
            // {
              overrides = {
                files = [
                  (toString ../fixtures/overrides/com.other.app)
                  (toString ../fixtures/overrides/org.gnome.Terminal)
                ];
              };
            };
          inherit pkgs lib installation;
          executionContext = "service-start";
        }).mkSaveStateCmd
      );
      expected = true;
    };
  }

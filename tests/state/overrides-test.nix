{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  jqScriptPath = ../../modules/flatpak/state/overrides.jq;

  # Runs the orphan-deletion loop against a temporary overrides directory.
  # Returns "exists" if `appId` is still present afterwards, "deleted" if not.
  runDeleteOrphanedTest = {
    appId,
    oldStateJson,
    newStateJson,
    overrideFilesJson ? "{}",
  }:
    builtins.readFile (pkgs.runCommand "delete-orphaned-${appId}" {
        buildInputs = [pkgs.jq pkgs.coreutils];
      } ''
        OVERRIDES_DIR=$(mktemp -d)
        touch "$OVERRIDES_DIR/${appId}"

        OLD_STATE='${oldStateJson}'
        NEW_STATE='${newStateJson}'

        for OVERRIDE_FILE in "$OVERRIDES_DIR"/*; do
          [[ -f "$OVERRIDE_FILE" ]] || continue
          APP_ID=$(${pkgs.coreutils}/bin/basename "$OVERRIDE_FILE")

          OVERRIDES_WAS_MANAGED=$(${pkgs.jq}/bin/jq -r -n \
            --arg app_id "$APP_ID" \
            --argjson old "$OLD_STATE" \
            '(($old.overrides.settings[$app_id] // $old.overrides[$app_id]) != null) or
             ($old.overrides.files // [] | map(split("/") | last) | index($app_id) != null)')

          OVERRIDES_IS_MANAGED=$(${pkgs.jq}/bin/jq -r -n \
            --arg app_id "$APP_ID" \
            --argjson new "$NEW_STATE" \
            '(($new.overrides.settings[$app_id] // $new.overrides[$app_id]) != null) or
             (($new.overrides._fileSettings[$app_id] // null) != null)')

          if [[ "$OVERRIDES_WAS_MANAGED" == "true" && "$OVERRIDES_IS_MANAGED" == "false" ]]; then
            ${pkgs.coreutils}/bin/rm -f "$OVERRIDE_FILE"
          fi
        done

        if [[ -f "$OVERRIDES_DIR/${appId}" ]]; then
          echo -n "exists" > $out
        else
          echo -n "deleted" > $out
        fi
      '');

  # Fixture override file paths (store-path-safe: toString of a Nix path literal)
  comOtherAppPath = toString ../fixtures/overrides/com.other.app;

  # install.nix instances for structural tests
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
  installWithPruneUnmanagedOverrides = import ../../modules/flatpak/install.nix {
    cfg =
      baseConfig
      // {
        overrides = {
          settings = {"com.example.app" = {"Context" = {"shared" = "network";};};};
          files = [(toString ../fixtures/overrides/com.other.app)];
          pruneUnmanagedOverrides = true;
        };
      };
    inherit pkgs lib installation;
    executionContext = "service-start";
  };
  installWithoutPruneUnmanagedOverrides = import ../../modules/flatpak/install.nix {
    cfg =
      baseConfig
      // {
        overrides = {
          settings = {"com.example.app" = {"Context" = {"shared" = "network";};};};
        };
      };
    inherit pkgs lib installation;
    executionContext = "service-start";
  };

  installWithReplaceMode = import ../../modules/flatpak/install.nix {
    cfg =
      baseConfig
      // {
        overrides = {
          writeMode = "replace";
          settings = {"com.example.app" = {"Context" = {"shared" = "network";};};};
          files = [comOtherAppPath];
        };
      };
    inherit pkgs lib installation;
    executionContext = "service-start";
  };

  installWithReplaceModeAndPrune = import ../../modules/flatpak/install.nix {
    cfg =
      baseConfig
      // {
        overrides = {
          writeMode = "replace";
          pruneUnmanagedOverrides = true;
          settings = {"com.example.app" = {"Context" = {"shared" = "network";};};};
        };
      };
    inherit pkgs lib installation;
    executionContext = "service-start";
  };

  installWithExplicitMergeMode = import ../../modules/flatpak/install.nix {
    cfg =
      baseConfig
      // {
        overrides = {
          writeMode = "merge";
          settings = {"com.example.app" = {"Context" = {"shared" = "network";};};};
        };
      };
    inherit pkgs lib installation;
    executionContext = "service-start";
  };

  runJqScript = {
    appId,
    newState,
    activeState,
    oldState ? "{}",
  }: let
    newFile = pkgs.writeTextFile {
      name = "new-state.json";
      text = newState;
    };
    activeFile = pkgs.writeTextFile {
      name = "active-state.json";
      text = activeState;
    };
    oldFile = pkgs.writeTextFile {
      name = "old-state.json";
      text = oldState;
    };
    output = builtins.readFile (pkgs.runCommand "jq-result" {
        buildInputs = [pkgs.jq];
      } ''
        ${pkgs.jq}/bin/jq -r -n \
          --arg app_id "${appId}" \
          --argjson new_state "$(cat ${newFile})" \
          --argjson active "$(cat ${activeFile})" \
          --argjson old_state "$(cat ${oldFile})" \
          --from-file ${jqScriptPath} > $out
      '');
  in
    builtins.toString output; # Preserve newline formatting for INI output
in
  runTests {
    testNoChanges = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides.settings = {"com.example.app" = {"Context" = {"shared" = "network";};};};};
        activeState = builtins.toJSON {"Context" = {"shared" = "network";};};
      };
      expected = "[Context]\nshared=network\n\n";
    };

    testNewOverrideAdded = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides.settings = {"com.example.app" = {"Context" = {"shared" = "network";};};};};
        activeState = builtins.toJSON {};
      };
      expected = "[Context]\nshared=network\n\n";
    };

    testOverrideRemoved = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides.settings = {"com.example.app" = {};};};
        activeState = builtins.toJSON {"Context" = {"shared" = "network";};};
      };
      # Active value preserved: settings no longer claims this key
      expected = "[Context]\nshared=network\n\n";
    };

    testOverrideUpdated = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides.settings = {"com.example.app" = {"Context" = {"shared" = "ipc";};};};};
        activeState = builtins.toJSON {"Context" = {"shared" = "network";};};
      };
      expected = "[Context]\nshared=ipc\n\n";
    };

    testMultipleSections = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides.settings = {
            "com.example.app" = {
              "Context" = {"shared" = "network;ipc";};
              "Permissions" = {"devices" = "all";};
            };
          };
        };
        activeState = builtins.toJSON {"Context" = {"shared" = "network";};};
      };
      expected = "[Context]\nshared=network;ipc\n\n[Permissions]\ndevices=all\n\n";
    };

    testFileSettingsOnly = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides._fileSettings."com.example.app" = {
            "Context" = {
              "shared" = "network";
              "devices" = "dri";
            };
          };
        };
        activeState = builtins.toJSON {};
      };
      expected = "[Context]\ndevices=dri\nshared=network\n\n";
    };

    testSettingsWinsOverFileSettings = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides = {
            settings."com.example.app" = {
              "Context" = {"shared" = "ipc";};
              "Permissions" = {"filesystems" = "home";};
            };
            _fileSettings."com.example.app" = {
              "Context" = {
                "shared" = "network";
                "devices" = "dri";
              };
            };
          };
        };
        activeState = builtins.toJSON {};
      };
      expected = "[Context]\ndevices=dri\nshared=ipc\n\n[Permissions]\nfilesystems=home\n\n";
    };

    testSettingsWinsOverFileSettingsArrays = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides = {
            settings."com.example.app" = {"Context" = {"shared" = ["ipc"];};};
            _fileSettings."com.example.app" = {
              "Context" = {
                "shared" = ["network"];
                "devices" = ["dri"];
              };
            };
          };
        };
        activeState = builtins.toJSON {};
      };
      expected = "[Context]\ndevices=dri\nshared=ipc\n\n";
    };

    testSettingsRemovedFileSettingsFallback = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides = {
            settings."com.example.app" = {"Context" = {"shared" = "x11";};};
            _fileSettings."com.example.app" = {
              "Context" = {
                "shared" = ["network"];
                "devices" = ["dri"];
              };
            };
          };
        };
        activeState = builtins.toJSON {"Context" = {"shared" = ["network" "ipc"];};};
      };
      expected = "[Context]\ndevices=dri\nshared=x11\n\n";
    };

    testComplexMergeScenario = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides = {
            settings."com.example.app" = {
              "Context" = {"shared" = ["ipc" "x11"];};
              "Environment" = {"LANG" = "en_US.UTF-8";};
            };
            _fileSettings."com.example.app" = {
              "Context" = {
                "shared" = ["pulseaudio"];
                "devices" = ["dri"];
              };
              "Permissions" = {"filesystems" = "home";};
            };
          };
        };
        activeState = builtins.toJSON {
          "Context" = {"shared" = ["network" "pulseaudio"];};
          "Permissions" = {"devices" = "all";};
        };
      };
      expected = "[Context]\ndevices=dri\nshared=ipc;x11\n\n[Environment]\nLANG=en_US.UTF-8\n\n[Permissions]\ndevices=all\nfilesystems=home\n\n";
    };

    testEmptyFileSettings = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides = {
            settings."com.example.app" = {"Context" = {"shared" = "network";};};
            _fileSettings = {};
          };
        };
        activeState = builtins.toJSON {};
      };
      expected = "[Context]\nshared=network\n\n";
    };

    testFileSettingsWithNoChanges = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides = {
            settings."com.example.app" = {"Context" = {"shared" = "network";};};
            _fileSettings = {};
          };
        };
        activeState = builtins.toJSON {"Context" = {"shared" = "network";};};
      };
      expected = "[Context]\nshared=network\n\n";
    };

    testFileSettingsWithMultipleApps = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides.settings = {
            "com.example.app" = {"Context" = {"shared" = "network";};};
            "com.example.otherapp" = {"Context" = {"shared" = "ipc";};};
          };
        };
        activeState = builtins.toJSON {};
      };
      expected = "[Context]\nshared=network\n\n";
    };

    testFileSettingsAuthoritativeOverActive = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides._fileSettings."com.example.app" = {"Context" = {"shared" = ["new" "content"];};};
        };
        activeState = builtins.toJSON {"Context" = {"shared" = ["old" "values"];};};
      };
      expected = "[Context]\nshared=new;content\n\n";
    };

    # _fileSettings wins over active for same key; active extras for other keys preserved
    testFileSettingsWithActiveExtras = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides._fileSettings."com.example.app" = {"Context" = {"sockets" = ["wayland" "x11"];};};
        };
        activeState = builtins.toJSON {"Context" = {"sockets" = ["wayland" "!x11"];};};
      };
      expected = "[Context]\nsockets=wayland;x11\n\n";
    };

    # settings wins; _fileSettings used for keys not in settings; active preserved for the rest
    testFileSettingsWithSettingsMerge = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides = {
            settings."com.example.app" = {"Environment" = {"LANG" = "en_US.UTF-8";};};
            _fileSettings."com.example.app" = {"Context" = {"shared" = ["network"];};};
          };
        };
        activeState = builtins.toJSON {"Context" = {"shared" = ["old"];};};
      };
      expected = "[Context]\nshared=network\n\n[Environment]\nLANG=en_US.UTF-8\n\n";
    };

    testSettingsRemovedPreservesActive = {
      expr = runJqScript {
        appId = "com.example.app";
        # settings no longer declares "shared"; active retains a manual edit
        newState = builtins.toJSON {overrides.settings = {"com.example.app" = {};};};
        activeState = builtins.toJSON {"Context" = {"shared" = ["network" "manual-add"];};};
      };
      expected = "[Context]\nshared=network;manual-add\n\n";
    };

    testSettingsPresentWinsOverActive = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides.settings = {"com.example.app" = {"Context" = {"shared" = ["network"];};};};};
        activeState = builtins.toJSON {"Context" = {"shared" = ["network" "manual-add"];};};
      };
      expected = "[Context]\nshared=network\n\n";
    };

    testFileRemovedUserEditPreserved = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides.settings = {};};
        # old_state has no _fileSettings for this app → key was a direct user edit
        oldState = builtins.toJSON {overrides._fileSettings = {};};
        activeState = builtins.toJSON {
          "Context" = {"shared" = ["user-edit-value"];};
        };
      };
      # User-typed key preserved since it was not in old _fileSettings
      expected = "[Context]\nshared=user-edit-value\n\n";
    };

    testFileRemovedStaleFileSettingsRetracted = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides.settings = {};};
        oldState = builtins.toJSON {
          overrides._fileSettings."com.example.app" = {
            "Context" = {"shared" = ["old-file-value"];};
          };
        };
        activeState = builtins.toJSON {
          "Context" = {"shared" = ["old-file-value"];};
        };
      };
      expected = "";
    };

    testFileRemovedPartialRetraction = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides.settings = {};};
        oldState = builtins.toJSON {
          overrides._fileSettings."com.example.app" = {
            "Context" = {"shared" = ["old-file-value"];};
          };
        };
        activeState = builtins.toJSON {
          "Context" = {
            "shared" = ["old-file-value"]; # from _fileSettings → retracted
            "devices" = "dri"; # direct user edit → preserved
          };
        };
      };
      expected = "[Context]\ndevices=dri\n\n";
    };

    testFileRemovedSettingsRemain = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides.settings."com.example.app" = {
            "Context" = {"shared" = ["network"];};
          };
        };
        activeState = builtins.toJSON {
          "Context" = {"shared" = ["old-file-value" "another-old"];};
        };
      };
      expected = "[Context]\nshared=network\n\n";
    };

    testFileRemovedNewSettingsAdded = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {
          overrides.settings."com.example.app" = {
            "Context" = {"shared" = ["ipc"];};
            "Environment" = {"LANG" = "en_US.UTF-8";};
          };
        };
        activeState = builtins.toJSON {
          "Context" = {
            "shared" = ["network" "pulseaudio"];
            "devices" = ["dri"];
          };
        };
      };
      expected = "[Context]\ndevices=dri\nshared=ipc\n\n[Environment]\nLANG=en_US.UTF-8\n\n";
    };

    testLegacyFormatBasic = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides = {"com.example.app" = {"Context" = {"shared" = "network";};};};};
        activeState = builtins.toJSON {"Context" = {"shared" = "network";};};
      };
      expected = "[Context]\nshared=network\n\n";
    };

    testLegacyFormatNewOverrideAdded = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides = {"com.example.app" = {"Context" = {"shared" = "ipc";};};};};
        activeState = builtins.toJSON {};
      };
      expected = "[Context]\nshared=ipc\n\n";
    };

    testLegacyFormatOverrideRemoved = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides = {"com.example.app" = {};};};
        activeState = builtins.toJSON {"Context" = {"shared" = "network";};};
      };
      expected = "[Context]\nshared=network\n\n";
    };

    testLegacyFormatOverrideUpdated = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides = {"com.example.app" = {"Context" = {"shared" = "x11";};};};};
        activeState = builtins.toJSON {"Context" = {"shared" = "network";};};
      };
      expected = "[Context]\nshared=x11\n\n";
    };

    testMixedFormatUpgrade = {
      expr = runJqScript {
        appId = "com.example.app";
        newState = builtins.toJSON {overrides.settings = {"com.example.app" = {"Context" = {"shared" = "ipc";};};};};
        activeState = builtins.toJSON {"Context" = {"shared" = "network";};};
      };
      expected = "[Context]\nshared=ipc\n\n";
    };

    testReplaceModeHasCpCmd = {
      expr = lib.strings.hasInfix "cp --no-preserve" installWithReplaceMode.mkOverridesCmd;
      expected = true;
    };

    testReplaceModeHasNoJcIni = {
      expr = lib.strings.hasInfix "jc --ini" installWithReplaceMode.mkOverridesCmd;
      expected = false;
    };

    testExplicitMergeModeHasJcIni = {
      expr = lib.strings.hasInfix "jc --ini" installWithExplicitMergeMode.mkOverridesCmd;
      expected = true;
    };

    testExplicitMergeModeHasNoCpCmd = {
      expr = lib.strings.hasInfix "cp --no-preserve" installWithExplicitMergeMode.mkOverridesCmd;
      expected = false;
    };

    testReplaceModeOverrideFilesNonEmpty = {
      expr = builtins.length (builtins.attrNames installWithReplaceMode.replaceOverrideFiles) > 0;
      expected = true;
    };

    testMergeModeReplaceOverrideFilesEmpty = {
      expr = installWithExplicitMergeMode.replaceOverrideFiles == {};
      expected = true;
    };

    testReplaceModeSettingsAppContent = {
      expr = builtins.readFile installWithReplaceMode.replaceOverrideFiles."com.example.app";
      expected = "[Context]\nshared=network\n";
    };

    testReplaceModeFileOnlyAppContent = {
      expr = builtins.readFile installWithReplaceMode.replaceOverrideFiles."com.other.app";
      expected = "[Context]\nshared=network\n";
    };

    testReplaceModeWithPruneChecksOldState = {
      expr = lib.strings.hasInfix "OVERRIDES_WAS_MANAGED" installWithReplaceModeAndPrune.mkOverridesCmd;
      expected = true;
    };

    testReplaceModeWithPruneHasRm = {
      expr = lib.strings.hasInfix "rm -f" installWithReplaceModeAndPrune.mkOverridesCmd;
      expected = true;
    };

    testReplaceModeWithoutPruneHasNoRm = {
      expr = lib.strings.hasInfix "rm -f" installWithReplaceMode.mkOverridesCmd;
      expected = false;
    };

    testPruneUnmanagedOverridesChecksOldState = {
      expr = lib.strings.hasInfix "OVERRIDES_WAS_MANAGED" installWithPruneUnmanagedOverrides.mkOverridesCmd;
      expected = true;
    };

    testPruneUnmanagedOverridesDisabledHasNoRm = {
      expr = lib.strings.hasInfix "rm -f" installWithoutPruneUnmanagedOverrides.mkOverridesCmd;
      expected = false;
    };

    testUnmanagedFileIsPreserved = {
      expr = runDeleteOrphanedTest {
        appId = "com.handcrafted.App";
        oldStateJson = builtins.toJSON {
          version = 2;
          overrides = {
            settings = {};
            files = [];
          };
          packages = [];
          remotes = [];
        };
        newStateJson = builtins.toJSON {
          version = 2;
          overrides = {
            settings = {};
            files = [];
          };
          packages = [];
          remotes = [];
        };
      };
      expected = "exists";
    };

    testPreviouslyManagedSettingsFileIsDeleted = {
      expr = runDeleteOrphanedTest {
        appId = "com.example.App";
        oldStateJson = builtins.toJSON {
          version = 2;
          overrides = {
            settings = {"com.example.App" = {Context = {shared = "network";};};};
            files = [];
          };
          packages = [];
          remotes = [];
        };
        newStateJson = builtins.toJSON {
          version = 2;
          overrides = {
            settings = {};
            files = [];
          };
          packages = [];
          remotes = [];
        };
      };
      expected = "deleted";
    };

    testPreviouslyManagedOverridesFileIsDeleted = {
      expr = runDeleteOrphanedTest {
        appId = "com.file.App";
        oldStateJson = builtins.toJSON {
          version = 2;
          overrides = {
            settings = {};
            files = ["/some/path/com.file.App"];
          };
          packages = [];
          remotes = [];
        };
        newStateJson = builtins.toJSON {
          version = 2;
          overrides = {
            settings = {};
            files = [];
          };
          packages = [];
          remotes = [];
        };
      };
      expected = "deleted";
    };

    testCurrentlyManagedFileIsPreserved = {
      expr = runDeleteOrphanedTest {
        appId = "com.example.App";
        oldStateJson = builtins.toJSON {
          version = 2;
          overrides = {
            settings = {"com.example.App" = {Context = {shared = "network";};};};
            files = [];
          };
          packages = [];
          remotes = [];
        };
        newStateJson = builtins.toJSON {
          version = 2;
          overrides = {
            settings = {"com.example.App" = {Context = {shared = "network";};};};
            files = [];
          };
          packages = [];
          remotes = [];
        };
      };
      expected = "exists";
    };

    testLegacyFormatManagedFileIsDeleted = {
      expr = runDeleteOrphanedTest {
        appId = "com.legacy.App";
        oldStateJson = builtins.toJSON {
          overrides = {"com.legacy.App" = {Context = {shared = "network";};};};
          packages = [];
          remotes = [];
        };
        newStateJson = builtins.toJSON {
          version = 2;
          overrides = {
            settings = {};
            files = [];
          };
          packages = [];
          remotes = [];
        };
      };
      expected = "deleted";
    };

    testFileSettingsManagedFileIsPreserved = {
      expr = runDeleteOrphanedTest {
        appId = "com.file.App";
        oldStateJson = builtins.toJSON {
          version = 2;
          overrides = {
            settings = {};
            files = ["/some/path/com.file.App"];
          };
          packages = [];
          remotes = [];
        };
        newStateJson = builtins.toJSON {
          version = 2;
          overrides = {
            settings = {};
            files = ["/some/path/com.file.App"];
            _fileSettings."com.file.App" = {Context = {shared = "network";};};
          };
          packages = [];
          remotes = [];
        };
      };
      expected = "exists";
    };

    # Legacy-format old state + writeMode="replace": the prune block in flatpakOverridesReplaceCmd
    # must contain the ($old.overrides[$app_id]) fallback so it correctly identifies apps that were
    # managed in a legacy-format generation (where app configs sit directly on overrides without a
    # .settings wrapper). Verified structurally: the jq expression is the same in both modes.
    testReplaceModeWithPruneHandlesLegacyOldState = {
      expr = lib.strings.hasInfix ''$old.overrides[$app_id]'' installWithReplaceModeAndPrune.mkOverridesCmd;
      expected = true;
    };
  }

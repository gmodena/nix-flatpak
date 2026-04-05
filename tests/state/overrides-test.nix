{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  jqScriptPath = ../../modules/flatpak/state/overrides.jq;
  runJqScript = { appId, oldState, newState, activeState, baseOverrides ? "{}", hasOverrideFile ? false, fileWasRemoved ? false }:
    let
      oldFile = pkgs.writeTextFile {
        name = "old-state.json";
        text = oldState;
      };
      newFile = pkgs.writeTextFile {
        name = "new-state.json";
        text = newState;
      };
      activeFile = pkgs.writeTextFile {
        name = "active-state.json";
        text = activeState;
      };
      baseFile = pkgs.writeTextFile {
        name = "base-overrides.json";
        text = baseOverrides;
      };
      hasOverrideFileStr = if hasOverrideFile then "true" else "false";
      fileWasRemovedStr = if fileWasRemoved then "true" else "false";
      output = builtins.readFile (pkgs.runCommand "jq-result" {
        buildInputs = [ pkgs.jq ];
      } ''
        ${pkgs.jq}/bin/jq -r -n \
          --arg app_id "${appId}" \
          --argjson old_state "$(cat ${oldFile})" \
          --argjson new_state "$(cat ${newFile})" \
          --argjson active "$(cat ${activeFile})" \
          --argjson base_overrides "$(cat ${baseFile})" \
          --argjson has_override_file ${hasOverrideFileStr} \
          --argjson file_was_removed ${fileWasRemovedStr} \
          --from-file ${jqScriptPath} > $out
      '');
    in
    builtins.toString output; # Preserve newline formatting for INI output
in
runTests {
  # Original tests (should still pass)
  testNoChanges = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  testNewOverrideAdded = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = { "com.example.app" = {}; }; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      activeState = builtins.toJSON { };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  testOverrideRemoved = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = {}; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "";
  };

  testOverrideUpdated = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "ipc"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=ipc\n\n";
  };

  testMultipleSections = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network;ipc"; }; "Permissions" = { "devices" = "all"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=network;ipc\n\n[Permissions]\ndevices=all\n\n";
  };

  # New tests for base overrides functionality
  testBaseOverridesOnly = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = {}; };
      newState = builtins.toJSON { overrides.settings = {}; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; "devices" = "dri"; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=network\n\n";
  };

  testBaseOverridesWithStateChanges = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = {}; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "ipc"; }; "Permissions" = { "filesystems" = "home"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; "devices" = "dri"; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=ipc\n\n[Permissions]\nfilesystems=home\n\n";
  };

  testBaseOverridesWithArrayMerging = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = {}; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = [ "ipc" ]; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = [ "network" ]; "devices" = [ "dri" ]; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=network;ipc\n\n";
  };

  testBaseOverridesWithOldStateRemoval = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "ipc"; }; }; }; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "x11"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = [ "network" "ipc" ]; }; };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = [ "network" ]; "devices" = [ "dri" ]; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=x11\n\n";
  };

  testBaseOverridesOverriddenByState = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = {}; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "x11"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; "devices" = "dri"; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=x11\n\n";
  };

  testComplexMergeScenario = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = [ "network" ]; }; "Permissions" = { "devices" = "all"; }; }; }; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = [ "ipc" "x11" ]; }; "Environment" = { "LANG" = "en_US.UTF-8"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = [ "network" "pulseaudio" ]; }; "Permissions" = { "devices" = "all"; }; };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = [ "pulseaudio" ]; "devices" = [ "dri" ]; }; "Permissions" = { "filesystems" = "home"; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=pulseaudio;ipc;x11\n\n[Environment]\nLANG=en_US.UTF-8\n\n[Permissions]\nfilesystems=home\n\n";
  };

  testEmptyBaseOverrides = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = {}; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  testBaseOverridesWithEmptyState = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = {}; };
      newState = builtins.toJSON { overrides.settings = {}; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  testBaseOverridesWithNoChanges = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
      baseOverrides = builtins.toJSON { };
    };
    expected = "[Context]\nshared=network\n\n";
  };
  
  testBaseOverridesWithMultipleApps = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = {}; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; "com.example.otherapp" = { "Context" = { "shared" = "ipc"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  testBaseOverridesWithMultipleAppsAndStateChanges = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = {}; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "ipc"; }; }; "com.example.otherapp" = { "Context" = { "shared" = "network"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=ipc\n\n";
  };

  testBaseOverridesWithMultipleAppsAndNoChanges = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; "com.example.otherapp" = { "Context" = { "shared" = "ipc"; }; }; }; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; "com.example.otherapp" = { "Context" = { "shared" = "ipc"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  # Override file is authoritative (fixes append bug)
  testOverrideFileAuthoritative = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = {}; };
      newState = builtins.toJSON { overrides.settings = {}; };
      activeState = builtins.toJSON { "Context" = { "shared" = [ "old" "values" ]; }; };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = [ "new" "content" ]; }; };
      hasOverrideFile = true;
    };
    expected = "[Context]\nshared=new;content\n\n";
  };

  # Override file replaces content completely
  testOverrideFileReplacesContent = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = {}; };
      newState = builtins.toJSON { overrides.settings = {}; };
      activeState = builtins.toJSON { "Context" = { "sockets" = [ "wayland" "!x11" ]; }; };
      baseOverrides = builtins.toJSON { "Context" = { "sockets" = [ "wayland" "x11" ]; }; };
      hasOverrideFile = true;
    };
    expected = "[Context]\nsockets=wayland;x11\n\n";
  };

  # Override file with nix settings merged
  testOverrideFileWithSettings = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = {}; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Environment" = { "LANG" = "en_US.UTF-8"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = [ "old" ]; }; };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = [ "network" ]; }; };
      hasOverrideFile = true;
    };
    expected = "[Context]\nshared=network\n\n[Environment]\nLANG=en_US.UTF-8\n\n";
  };

  # Without override file, manual changes are preserved
  testNoOverrideFilePreservesManualChanges = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = [ "network" ]; }; }; }; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = [ "network" ]; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = [ "network" "manual-add" ]; }; };
      baseOverrides = builtins.toJSON { };
      hasOverrideFile = false;
    };
    # Order: (active - old) comes before new in the formula
    expected = "[Context]\nshared=manual-add;network\n\n";
  };

  # When file is removed but settings remain, file-based content should be cleared
  testFileRemovedSettingsRemain = {
    expr = runJqScript {
      appId = "com.example.app";
      # Old state had the app configured via files
      oldState = builtins.toJSON {
        overrides = {
          settings = {};
          files = [ "/path/to/com.example.app" ];
        };
      };
      # New state has settings for the app but no file
      newState = builtins.toJSON {
        overrides.settings = {
          "com.example.app" = {
            "Context" = { "shared" = [ "network" ]; };
          };
        };
      };
      # Active state contains values from the old file
      activeState = builtins.toJSON {
        "Context" = { "shared" = [ "old-file-value" "another-old" ]; };
      };
      baseOverrides = builtins.toJSON { };
      hasOverrideFile = false;
      fileWasRemoved = true;
    };
    # File content should be cleared, only new settings remain
    expected = "[Context]\nshared=network\n\n";
  };

  # File removed with no settings. Authoritative merge clears everything
  testFileRemovedNoSettingsAuthoritative = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON {
        overrides = {
          settings = {};
          files = [ "/path/to/com.example.app" ];
        };
      };
      newState = builtins.toJSON { overrides.settings = {}; };
      # Active state contains old file values that should be cleared
      activeState = builtins.toJSON {
        "Context" = { "shared" = [ "old-file-value" ]; };
      };
      baseOverrides = builtins.toJSON { };
      hasOverrideFile = false;
      fileWasRemoved = true;
    };
    # Everything should be cleared (empty output)
    expected = "";
  };

  # File removed but new settings added for same entry
  testFileRemovedNewSettingsAdded = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON {
        overrides = {
          settings = {};
          files = [ "/path/to/com.example.app" ];
        };
      };
      newState = builtins.toJSON {
        overrides.settings = {
          "com.example.app" = {
            "Context" = { "shared" = [ "ipc" ]; };
            "Environment" = { "LANG" = "en_US.UTF-8"; };
          };
        };
      };
      activeState = builtins.toJSON {
        "Context" = { "shared" = [ "network" "pulseaudio" ]; "devices" = [ "dri" ]; };
      };
      baseOverrides = builtins.toJSON { };
      hasOverrideFile = false;
      fileWasRemoved = true;
    };
    # Old file content cleared, only new settings applied
    expected = "[Context]\nshared=ipc\n\n[Environment]\nLANG=en_US.UTF-8\n\n";
  };

  # File not removed from `files`. Manual changes should still be preserved
  testFileNotRemovedPreservesManual = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON {
        overrides.settings = { "com.example.app" = { "Context" = { "shared" = [ "network" ]; }; }; };
      };
      newState = builtins.toJSON {
        overrides.settings = { "com.example.app" = { "Context" = { "shared" = [ "network" ]; }; }; };
      };
      activeState = builtins.toJSON {
        "Context" = { "shared" = [ "network" "manual-change" ]; };
      };
      baseOverrides = builtins.toJSON { };
      hasOverrideFile = false;
      fileWasRemoved = false;
    };
    # Manual changes preserved because file was not removed
    expected = "[Context]\nshared=manual-change;network\n\n";
  };

  # Backwards compatibility tests for legacy format (overrides without .settings)
  testLegacyFormatBasic = {
    expr = runJqScript {
      appId = "com.example.app";
      # Legacy format: overrides contains app configs (no .settings attribute)
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  testLegacyFormatNewOverrideAdded = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = {}; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "ipc"; }; }; }; };
      activeState = builtins.toJSON { };
    };
    expected = "[Context]\nshared=ipc\n\n";
  };

  testLegacyFormatOverrideRemoved = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = {}; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "";
  };

  testLegacyFormatOverrideUpdated = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "x11"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=x11\n\n";
  };

  # Mixed format: old state in legacy format, new state in new format.
  testMixedFormatUpgrade = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides.settings = { "com.example.app" = { "Context" = { "shared" = "ipc"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=ipc\n\n";
  };
}

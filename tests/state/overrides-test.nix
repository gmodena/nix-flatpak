{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  jqScriptPath = ../../modules/flatpak/state/overrides.jq;
  runJqScript = { appId, oldState, newState, activeState, baseOverrides ? "{}" }:
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
      output = builtins.readFile (pkgs.runCommand "jq-result" {
        buildInputs = [ pkgs.jq ];
      } ''
        ${pkgs.jq}/bin/jq -r -n \
          --arg app_id "${appId}" \
          --argjson old_state "$(cat ${oldFile})" \
          --argjson new_state "$(cat ${newFile})" \
          --argjson active "$(cat ${activeFile})" \
          --argjson base_overrides "$(cat ${baseFile})" \
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
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  testNewOverrideAdded = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = {}; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      activeState = builtins.toJSON { };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  testOverrideRemoved = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = {}; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "";
  };

  testOverrideUpdated = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "ipc"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=ipc\n\n";
  };

  testMultipleSections = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network;ipc"; }; "Permissions" = { "devices" = "all"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=network;ipc\n\n[Permissions]\ndevices=all\n\n";
  };

  # New tests for base overrides functionality
  testBaseOverridesOnly = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = {}; };
      newState = builtins.toJSON { overrides = {}; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; "devices" = "dri"; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=network\n\n";
  };

  testBaseOverridesWithStateChanges = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = {}; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "ipc"; }; "Permissions" = { "filesystems" = "home"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; "devices" = "dri"; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=ipc\n\n[Permissions]\nfilesystems=home\n\n";
  };

  testBaseOverridesWithArrayMerging = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = {}; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = [ "ipc" ]; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = [ "network" ]; "devices" = [ "dri" ]; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=network;ipc\n\n";
  };

  testBaseOverridesWithOldStateRemoval = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "ipc"; }; }; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "x11"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = [ "network" "ipc" ]; }; };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = [ "network" ]; "devices" = [ "dri" ]; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=x11\n\n";
  };

  testBaseOverridesOverriddenByState = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = {}; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "x11"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; "devices" = "dri"; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=x11\n\n";
  };

  testComplexMergeScenario = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = [ "network" ]; }; "Permissions" = { "devices" = "all"; }; }; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = [ "ipc" "x11" ]; }; "Environment" = { "LANG" = "en_US.UTF-8"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = [ "network" "pulseaudio" ]; }; "Permissions" = { "devices" = "all"; }; };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = [ "pulseaudio" ]; "devices" = [ "dri" ]; }; "Permissions" = { "filesystems" = "home"; }; };
    };
    expected = "[Context]\ndevices=dri\nshared=pulseaudio;ipc;x11\n\n[Environment]\nLANG=en_US.UTF-8\n\n[Permissions]\nfilesystems=home\n\n";
  };

  testEmptyBaseOverrides = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = {}; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  testBaseOverridesWithEmptyState = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = {}; };
      newState = builtins.toJSON { overrides = {}; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  testBaseOverridesWithNoChanges = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; }; };
      activeState = builtins.toJSON { "Context" = { "shared" = "network"; }; };
      baseOverrides = builtins.toJSON { };
    };
    expected = "[Context]\nshared=network\n\n";
  };
  
  testBaseOverridesWithMultipleApps = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = {}; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; "com.example.otherapp" = { "Context" = { "shared" = "ipc"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=network\n\n";
  };

  testBaseOverridesWithMultipleAppsAndStateChanges = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = {}; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "ipc"; }; }; "com.example.otherapp" = { "Context" = { "shared" = "network"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { "Context" = { "shared" = "network"; }; };
    };
    expected = "[Context]\nshared=ipc\n\n";
  };

  testBaseOverridesWithMultipleAppsAndNoChanges = {
    expr = runJqScript {
      appId = "com.example.app";
      oldState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; "com.example.otherapp" = { "Context" = { "shared" = "ipc"; }; }; }; };
      newState = builtins.toJSON { overrides = { "com.example.app" = { "Context" = { "shared" = "network"; }; }; "com.example.otherapp" = { "Context" = { "shared" = "ipc"; }; }; }; };
      activeState = builtins.toJSON { };
      baseOverrides = builtins.toJSON { };
    };
    expected = "[Context]\nshared=network\n\n";
  };
}

{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;

  jqScriptPath = ../../modules/flatpak/state/overrides.jq;

  runJqScript = { appId, oldState, newState, activeState }:
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
      output = builtins.readFile (pkgs.runCommand "jq-result" {
        buildInputs = [ pkgs.jq ];
      } ''
        ${pkgs.jq}/bin/jq -r -n \
          --arg app_id "${appId}" \
          --argjson old_state "$(cat ${oldFile})" \
          --argjson new_state "$(cat ${newFile})" \
          --argjson active "$(cat ${activeFile})" \
          --from-file ${jqScriptPath} > $out
      '');
    in
      builtins.toString output; # Preserve newline formatting for INI output

in runTests {
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
}
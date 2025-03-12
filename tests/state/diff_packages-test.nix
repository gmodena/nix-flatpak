{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;

  jqScriptPath = ../../modules/flatpak/state/diff_packages.jq;

  runJqScript = { oldState, newState }:
let
  oldFile = pkgs.writeTextFile {
    name = "old-state.json";
    text = oldState;
  };
  newFile = pkgs.writeTextFile {
    name = "new-state.json";
    text = newState;
  };
  rawOutput = builtins.readFile (pkgs.runCommand "jq-result" {
    buildInputs = [ pkgs.jq ];
  } ''
    ${pkgs.jq}/bin/jq -r -n \
      --argjson old "$(cat ${oldFile})" \
      --argjson new "$(cat ${newFile})" \
      --from-file ${jqScriptPath} > $out
  '');
  # Handle the case where jq outputs nothing
  output = if builtins.stringLength (lib.removeSuffix "\n" rawOutput) == 0 
           then []
           else lib.filter (x: x != "") (lib.splitString "\n" (lib.removeSuffix "\n" rawOutput));
in
  output;

in runTests {
  testNoDifference = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = ["com.example.app"]; remotes = []; };
      newState = builtins.toJSON { packages = ["com.example.app"]; remotes = []; };
    };
    expected = [];
  };

  testRemovedOldFormat = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = ["com.example.app" "com.old.app"]; remotes = []; };
      newState = builtins.toJSON { packages = ["com.example.app"]; remotes = []; };
    };
    expected = ["com.old.app"];
  };

  testRemovedNewFormat = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = [{ appId = "com.example.app"; } { appId = "com.old.app"; }]; remotes = []; };
      newState = builtins.toJSON { packages = [{ appId = "com.example.app"; }]; remotes = []; };
    };
    expected = ["com.old.app"];
  };

  testMixedFormat = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = ["com.legacy.app" { appId = "com.new.app"; }]; remotes = []; };
      newState = builtins.toJSON { packages = [{ appId = "com.new.app"; }]; remotes = []; };
    };
    expected = ["com.legacy.app"];
  };

  testAllRemoved = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = ["com.old.app" { appId = "com.very.old.app"; }]; remotes = []; };
      newState = builtins.toJSON { packages = []; remotes = []; };
    };
    expected = ["com.old.app" "com.very.old.app"];
  };
}

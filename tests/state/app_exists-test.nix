{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  
  jqScriptPath = ../../modules/flatpak/state/app_exists.jq;
  
  runJqScript = { oldState, appId }:
    let
      jsonFile = pkgs.writeTextFile {
        name = "old-state.json";
        text = oldState;
      };
      
      output = builtins.readFile (pkgs.runCommand "jq-result" {
        buildInputs = [ pkgs.jq ];
        APPID = appId;
      } ''
        ${pkgs.jq}/bin/jq -r -n \
          --argjson old "$(cat ${jsonFile})" \
          --arg appId "$APPID" \
          --from-file ${jqScriptPath} > $out
      '');
    in
      lib.removeSuffix "\n" output;
in
runTests {
  testNullPackages = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = null; };
      appId = "com.example.app";
    };
    expected = "false";
  };
  
  testEmptyPackages = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = []; };
      appId = "com.example.app";
    };
    expected = "false";
  };
  
  testOldFormatAppExists = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = ["com.example.app" "com.other.app"]; };
      appId = "com.example.app";
    };
    expected = "true";
  };
  
  testOldFormatAppMissing = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = ["com.other1.app" "com.other2.app"]; };
      appId = "com.example.app";
    };
    expected = "false";
  };
  
  testNewFormatAppExists = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = [{ appId = "com.example.app"; version = "1.0"; } { appId = "com.other.app"; version = "2.0"; }]; };
      appId = "com.example.app";
    };
    expected = "true";
  };
  
  testNewFormatAppMissing = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = [{ appId = "com.other1.app"; version = "1.0"; } { appId = "com.other2.app"; version = "2.0"; }]; };
      appId = "com.example.app";
    };
    expected = "false";
  };
  
  testUnexpectedFormat = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = [1 2 3]; };
      appId = "com.example.app";
    };
    expected = "false";
  };
  
  testMixedFormat = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = ["com.first.app" { appId = "com.example.app"; }]; };
      appId = "com.example.app";
    };
    expected = "true";
  };
}
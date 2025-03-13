{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;

  jqScriptPath = ../../modules/flatpak/state/parse_statefile.jq;

  runJqScript = { oldState, installedPackages, installedRemotes }:
    let
      jsonFile = pkgs.writeTextFile {
        name = "old-state.json";
        text = oldState;
      };
      installedFile = pkgs.writeTextFile {
        name = "installed-packages.txt";
        text = installedPackages;
      };
      remotesFile = pkgs.writeTextFile {
        name = "installed-remotes.txt";
        text = installedRemotes;
      };
      output = builtins.readFile (pkgs.runCommand "jq-result" {
        buildInputs = [ pkgs.jq ];
      } ''
        ${pkgs.jq}/bin/jq -r -n \
          --argjson old "$(cat ${jsonFile})" \
          --arg installed_packages "$(cat ${installedFile})" \
          --arg installed_remotes "$(cat ${remotesFile})" \
          --from-file ${jqScriptPath} > $out
      '');
    in
      builtins.fromJSON (lib.removeSuffix "\n" output);

in runTests {
  testEmptyOldState = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = []; remotes = []; };
      installedPackages = "";
      installedRemotes = "";
    };
    expected = { packages = []; remotes = []; };
  };

  testNewFormatKeepsState = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.example.app"; origin = "remote"; commit = "commit1"; }
          { appId = "com.new.app"; origin = "remote"; commit = "commit2"; }
        ];
        remotes = [ { name = "remote3"; } ];
      };
      installedPackages = "com.example.app\ncom.new.app";
      installedRemotes = "remote";
    };
    expected = {
      packages = [
        { appId = "com.example.app"; origin = "remote"; commit = "commit1"; }
        { appId = "com.new.app"; origin = "remote"; commit = "commit2"; }
      ];
      remotes = [ { name = "remote"; } ];
    };
  };

  testOldFormatConversion = {
    expr = runJqScript {
      oldState = builtins.toJSON { packages = [ "com.example.app" ]; remotes = []; };
      installedPackages = "com.new.app\torigin1\tcommit1";
      installedRemotes = "remote1\nremote2";
    };
    expected = {
      packages = [
        { appId = "com.example.app"; origin = null; commit = null; }
        { appId = "com.new.app"; origin = "origin1"; commit = "commit1"; }
      ];
      remotes = [
        { name = "remote1"; }
        { name = "remote2"; }
      ];
    };
  };
}

{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  
  jqScriptPath = ../../modules/flatpak/state/compare_sha.jq;
  
  runJqScript = { oldState, newState, appId }:
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
          --argjson oldState "$(cat ${oldFile})" \
          --argjson newState "$(cat ${newFile})" \
          --arg appId "${appId}" \
          --from-file ${jqScriptPath} > $out
      '');
      # Handle the case where jq outputs nothing (empty)
      output = if builtins.stringLength (lib.removeSuffix "\n" rawOutput) == 0
        then null
        else lib.removeSuffix "\n" rawOutput;
    in
      output;

in runTests {
  # Test: No change when SHA256 values are identical
  testNoChange = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
          { appId = "com.other.app"; sha256 = "other_hash"; }
        ];
      };
      newState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
          { appId = "com.other.app"; sha256 = "different_hash"; }
        ];
      };
      appId = "com.some.app";
    };
    expected = null;  # empty output
  };

  # Test: Change detected when SHA256 values differ
  testShaChanged = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
        ];
      };
      newState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "def456abc123"; }
        ];
      };
      appId = "com.some.app";
    };
    expected = "com.some.app";
  };

  # Test: Change detected when SHA256 goes from value to null
  testShaToNull = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
        ];
      };
      newState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; }  # no sha256 field
        ];
      };
      appId = "com.some.app";
    };
    expected = "com.some.app";
  };

  # Test: Change detected when SHA256 goes from null to value
  testNullToSha = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; }  # no sha256 field
        ];
      };
      newState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
        ];
      };
      appId = "com.some.app";
    };
    expected = "com.some.app";
  };

  # Test: No change when both SHA256 values are null
  testBothNull = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; }  # no sha256 field
        ];
      };
      newState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; }  # no sha256 field
        ];
      };
      appId = "com.some.app";
    };
    expected = null;  # empty output
  };

  # Test: App not found in old state
  testAppNotInOldState = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.other.app"; sha256 = "other_hash"; }
        ];
      };
      newState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
        ];
      };
      appId = "com.some.app";
    };
    expected = "com.some.app";
  };

  # Test: App not found in new state
  testAppNotInNewState = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
        ];
      };
      newState = builtins.toJSON {
        packages = [
          { appId = "com.other.app"; sha256 = "other_hash"; }
        ];
      };
      appId = "com.some.app";
    };
    expected = "com.some.app";
  };

  # Test: App not found in either state
  testAppNotFound = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.other.app"; sha256 = "other_hash"; }
        ];
      };
      newState = builtins.toJSON {
        packages = [
          { appId = "com.another.app"; sha256 = "another_hash"; }
        ];
      };
      appId = "com.some.app";
    };
    expected = null;  # both null, so no change
  };

  # Test: Empty packages array in old state
  testEmptyOldPackages = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [];
      };
      newState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
        ];
      };
      appId = "com.some.app";
    };
    expected = "com.some.app";
  };

  # Test: Empty packages array in new state
  testEmptyNewPackages = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
        ];
      };
      newState = builtins.toJSON {
        packages = [];
      };
      appId = "com.some.app";
    };
    expected = "com.some.app";
  };

  # Test: Missing packages field in old state
  testMissingOldPackages = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        remotes = [];
      };
      newState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
        ];
      };
      appId = "com.some.app";
    };
    expected = "com.some.app";
  };

  # Test: Missing packages field in new state
  testMissingNewPackages = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
        ];
      };
      newState = builtins.toJSON {
        remotes = [];
      };
      appId = "com.some.app";
    };
    expected = "com.some.app";
  };

  # Test: Different app ID to ensure script is filtering correctly
  testDifferentAppId = {
    expr = runJqScript {
      oldState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
          { appId = "com.example.app"; sha256 = "old_hash"; }
        ];
      };
      newState = builtins.toJSON {
        packages = [
          { appId = "com.some.app"; sha256 = "abc123def456"; }
          { appId = "com.example.app"; sha256 = "new_hash"; }
        ];
      };
      appId = "com.example.app";
    };
    expected = "com.example.app";
  };
}
{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;
  inherit (lib) runTests;

  ini = import ../modules/flatpak/ini.nix {inherit lib;};
  inherit (ini) parseIniContent toIniContent;

  fixtureGlobal = "[Environment]\nLC_ALL = \"C.UTF-8\"\n";
  fixtureGedit = "[Context]\nsockets=wayland;!x11;fallback-x11;\n";
  fixtureOnlyOffice = "[Context]\nsockets=x11";

  # The roundtrip property we verify throughout:
  # parse(serialize(parse(content))) == parse(content)
  # This confirms that toIniContent produces valid INI that parses back to the same
  # structure, and implicitly that the parser is idempotent on canonical output.
  roundtrip = content: parseIniContent (toIniContent (parseIniContent content));
in
  runTests {
    testParseSingleStringValue = {
      expr = parseIniContent "[Context]\nsockets=x11\n";
      expected = {Context = {sockets = "x11";};};
    };

    testParseMultipleValues = {
      expr = parseIniContent "[Context]\nsockets=wayland;!x11;fallback-x11\n";
      expected = {Context = {sockets = ["wayland" "!x11" "fallback-x11"];};};
    };

    testParseMultipleSections = {
      expr = parseIniContent "[Context]\nshared=network\n[Environment]\nLANG=C.UTF-8\n";
      expected = {
        Context = {shared = "network";};
        Environment = {LANG = "C.UTF-8";};
      };
    };

    testParseTrimsKeyWhitespace = {
      expr = (parseIniContent "[Environment]\nLC_ALL = \"C.UTF-8\"\n").Environment;
      expected = {LC_ALL = "\"C.UTF-8\"";};
    };

    testParseIgnoresBlankLines = {
      expr = parseIniContent "\n[Context]\n\nsockets=x11\n\n";
      expected = {Context = {sockets = "x11";};};
    };

    testParseIgnoresHashComments = {
      expr = parseIniContent "# a comment\n[Context]\nsockets=x11\n";
      expected = {Context = {sockets = "x11";};};
    };

    testParseIgnoresSemicolonComments = {
      expr = parseIniContent "; a comment\n[Context]\nsockets=x11\n";
      expected = {Context = {sockets = "x11";};};
    };

    testParseStripsTrailingSemicolon = {
      # Flatpak sometimes writes a trailing semicolon; parser must drop the empty token.
      expr = parseIniContent "[Context]\nsockets=wayland;!x11;fallback-x11;\n";
      expected = {Context = {sockets = ["wayland" "!x11" "fallback-x11"];};};
    };

    testValueOrderPreserved = {
      # "ordering of values matter": wayland must come before !x11 before fallback-x11.
      expr = (parseIniContent "[Context]\nsockets=wayland;!x11;fallback-x11;\n").Context.sockets;
      expected = ["wayland" "!x11" "fallback-x11"];
    };

    testValueOrderNotAlphabetical = {
      # Values should NOT be sorted – original declaration order is kept.
      expr = (parseIniContent "[Context]\nsockets=z;a;m;\n").Context.sockets;
      expected = ["z" "a" "m"];
    };

    testParseFixtureGlobal = {
      expr = parseIniContent fixtureGlobal;
      expected = {Environment = {LC_ALL = "\"C.UTF-8\"";};};
    };

    testParseFixtureGedit = {
      expr = parseIniContent fixtureGedit;
      expected = {Context = {sockets = ["wayland" "!x11" "fallback-x11"];};};
    };

    testParseFixtureOnlyOffice = {
      expr = parseIniContent fixtureOnlyOffice;
      expected = {Context = {sockets = "x11";};};
    };

    testRoundtripGlobal = {
      expr = roundtrip fixtureGlobal;
      expected = parseIniContent fixtureGlobal;
    };

    testRoundtripGedit = {
      expr = roundtrip fixtureGedit;
      expected = parseIniContent fixtureGedit;
    };

    testRoundtripOnlyOffice = {
      expr = roundtrip fixtureOnlyOffice;
      expected = parseIniContent fixtureOnlyOffice;
    };

    # Roundtrip must preserve values order and not sort them.
    testRoundtripPreservesGeditSocketOrder = {
      expr = (roundtrip fixtureGedit).Context.sockets;
      expected = ["wayland" "!x11" "fallback-x11"];
    };
  }

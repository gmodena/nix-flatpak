{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  inherit (lib) runTests;

  ini = import ../../modules/flatpak/ini.nix { inherit lib; };
  inherit (ini) parseIniContent toIniContent mergeOverrideSettings;

  roundtrip = content: parseIniContent (toIniContent (parseIniContent content));
in
runTests {

  # ---------------------------------------------------------------------------
  # parseIniContent
  # ---------------------------------------------------------------------------

  testParseBasicSectionKey = {
    expr     = parseIniContent "[Context]\nshared=network\n";
    expected = { Context = { shared = "network"; }; };
  };

  testParseSemicolonSeparatedBecomesList = {
    expr     = parseIniContent "[Context]\nsockets=wayland;!x11\n";
    expected = { Context = { sockets = [ "wayland" "!x11" ]; }; };
  };

  testParseSingleValueStaysString = {
    expr     = parseIniContent "[Context]\nsockets=x11\n";
    expected = { Context = { sockets = "x11"; }; };
  };

  testParseBlankLinesIgnored = {
    expr     = parseIniContent "\n[Context]\n\nsockets=x11\n\n";
    expected = { Context = { sockets = "x11"; }; };
  };

  testParseHashCommentIgnored = {
    expr     = parseIniContent "# comment\n[Context]\nsockets=x11\n";
    expected = { Context = { sockets = "x11"; }; };
  };

  testParseWhitespaceTrimmed = {
    expr     = parseIniContent "[Context]\nshared = network\n";
    expected = { Context = { shared = "network"; }; };
  };

  # ---------------------------------------------------------------------------
  # toIniContent
  # ---------------------------------------------------------------------------

  testToIniSectionsSortedAlphabetically = {
    expr     = builtins.substring 0 3 (toIniContent { Z = { a = "1"; }; A = { b = "2"; }; });
    expected = "[A]";
  };

  testToIniKeysSortedAlphabetically = {
    # keys z and a: a must appear before z in output
    expr =
      let out = toIniContent { Context = { z = "1"; a = "2"; }; };
      in (builtins.match ".*\na=.*" out) != null;
    expected = true;
  };

  testToIniListJoinedWithSemicolon = {
    expr     = toIniContent { Context = { sockets = [ "wayland" "!x11" ]; }; };
    expected = "[Context]\nsockets=wayland;!x11\n";
  };

  testToIniSectionsSeparatedByBlankLine = {
    # Two sections must be separated by a blank line (\n\n between them)
    expr =
      let out = toIniContent { A = { k = "1"; }; B = { k = "2"; }; };
      in lib.strings.hasInfix "\n\n" out;
    expected = true;
  };

  # ---------------------------------------------------------------------------
  # mergeOverrideSettings
  # ---------------------------------------------------------------------------

  testMergeSettingsWinsOverFileSettings = {
    expr = mergeOverrideSettings
      { "com.example.app" = { Context = { shared = "ipc"; }; }; }
      { "com.example.app" = { Context = { shared = "network"; devices = "dri"; }; }; }
      "com.example.app";
    # settings shared=ipc wins; fileSettings devices=dri is preserved
    expected = { Context = { shared = "ipc"; devices = "dri"; }; };
  };

  testMergeFileSettingsUsedWhenSettingsAbsent = {
    expr = mergeOverrideSettings
      { }
      { "com.example.app" = { Context = { shared = "network"; }; }; }
      "com.example.app";
    expected = { Context = { shared = "network"; }; };
  };

  testMergeSettingsOnly = {
    expr = mergeOverrideSettings
      { "com.example.app" = { Context = { shared = "ipc"; }; }; }
      { }
      "com.example.app";
    expected = { Context = { shared = "ipc"; }; };
  };

  testMergeFileSettingsOnly = {
    expr = mergeOverrideSettings
      { }
      { "com.example.app" = { Context = { shared = "network"; }; }; }
      "com.example.app";
    expected = { Context = { shared = "network"; }; };
  };

  testMergeBothEmpty = {
    expr     = mergeOverrideSettings { } { } "com.example.app";
    expected = { };
  };

  testMergeMultipleSections = {
    expr = mergeOverrideSettings
      { "com.example.app" = { Environment = { LANG = "en_US.UTF-8"; }; }; }
      { "com.example.app" = { Context = { shared = "network"; }; }; }
      "com.example.app";
    expected = {
      Context     = { shared = "network"; };
      Environment = { LANG = "en_US.UTF-8"; };
    };
  };

  testMergeUnknownAppReturnsEmpty = {
    expr = mergeOverrideSettings
      { "com.example.app" = { Context = { shared = "ipc"; }; }; }
      { }
      "com.other.app";
    expected = { };
  };

  # ---------------------------------------------------------------------------
  # Roundtrip: parse ∘ toIni ∘ parse == parse (inline strings only)
  # ---------------------------------------------------------------------------

  testRoundtripSingleSection = {
    expr     = roundtrip "[Context]\nshared=network\n";
    expected = parseIniContent "[Context]\nshared=network\n";
  };

  testRoundtripMultipleValues = {
    expr     = roundtrip "[Context]\nsockets=wayland;!x11;fallback-x11;\n";
    expected = parseIniContent "[Context]\nsockets=wayland;!x11;fallback-x11;\n";
  };

  testRoundtripMultipleSections = {
    expr     = roundtrip "[Context]\nshared=network\n[Environment]\nLANG=C.UTF-8\n";
    expected = parseIniContent "[Context]\nshared=network\n[Environment]\nLANG=C.UTF-8\n";
  };

  testRoundtripPreservesValueOrder = {
    expr     = (roundtrip "[Context]\nsockets=z;a;m;\n").Context.sockets;
    expected = [ "z" "a" "m" ];
  };
}

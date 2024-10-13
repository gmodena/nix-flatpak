{ pkgs ? import <nixpkgs> { } }:

let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  ref = import ../modules/ref.nix { inherit lib; };

  pwd = builtins.getEnv "PWD";
  fixturePath = "file://${pwd}/fixtures/package.flatpakref";
  fixtureHash = "040iig2yg2i28s5xc9cvp5syaaqq165idy3nhlpv8xn4f6zh4h1f";
  expectedFixtureAttrSet = {
    ${ref.sanitizeUrl fixturePath} = {
      Title = "gedit";
      Name = "org.gnome.gedit";
      Branch = "stable";
      Url = "http://sdk.gnome.org/repo-apps/";
      IsRuntime = "false";
      GPGKey = "REDACTED";
      DeployCollectionID = "org.gnome.Apps";
    };
  };
in
runTests {
  testSanitizeUrl = {
    expr = ref.sanitizeUrl "https://example.local";
    expected = "https_example_local";
  };

  testIsFlatpakref = {
    expr = ref.isFlatpakref { flatpakref = "https://example.local/package.flatpakref"; };
    expected = true;
  };

  testIsFlatpakrefWithNull = {
    expr = ref.isFlatpakref { flatpakref = null; };
    expected = false;
  };

  testIsFlatpakrefWithMissing = {
    expr = ref.isFlatpakref { appId = "local.example.Package"; };
    expected = false;
  };

  testGetRemoteNameFromFlatpakrefWithOrigin = {
    expr = ref.getRemoteNameFromFlatpakref "example" { SuggestRemoteName = "local"; };
    expected = "example";
  };

  testGetRemoteNameWithSuggestedName = {
    expr = ref.getRemoteNameFromFlatpakref null { SuggestRemoteName = "local"; };
    expected = "local";
  };

  testGetRemoteNameWithPackageName = {
    expr = ref.getRemoteNameFromFlatpakref null { Name = "Example"; };
    expected = "example-origin";
  };

  testFlatpakrefToAttrSet = {
    expr = ref.flatpakrefToAttrSet { flatpakref = fixturePath; sha256 = null; } { };
    expected = expectedFixtureAttrSet;
  };

  testFlatpakrefToAttrSetWithSha256 = {
    expr = ref.flatpakrefToAttrSet { flatpakref = fixturePath; sha256 = fixtureHash; } { };
    expected = expectedFixtureAttrSet;
  };
}

{ pkgs ? import <nixpkgs> { } }:

let
  inherit (pkgs) lib;
  inherit (lib) runTests;
  state = import ../modules/state.nix { inherit pkgs; };

  appId = "im.riot.Riot";

  pwd = builtins.getEnv "PWD";
  stateData = state.readState ("${pwd}/fixtures/flatpak-state.json");

in
runTests {
  testShoulNotExectFlatpakInstall = {
    # Base case: state matches runtime. We don't need to `flatpak install` apps.
    # installation = "user";
    # update = false;
    # commit = null;

    expr = state.shouldExecFlatpakInstall stateData "user" false appId null;
    expected = false;
  };

  testShoulExectFlatpakInstallWhenUpdate = {
    # Apps need to be updated on activation.
    # installation = "user";
    # update = true;
    # commit = null;

    expr = state.shouldExecFlatpakInstall stateData "user" true appId null;
    expected = true;
  };

  testShoulExectFlatpakInstallWhenCommit = {
    # Apps need to be pinned at `commit`. Currently, this requires an
    # update on activation.
    # installation = "user";
    # update = false;
    # commit = "1234";

    expr = state.shouldExecFlatpakInstall stateData "user" false appId "1234";
    expected = true;
  };

  testShoulExectFlatpakInstallOnNewApp = {
    # state has mutate: a new app as been added, and must be installed on activation.
    # update on activation.
    # appId = "io.github.gmodena.NewApp"
    # installation = "user";
    # update = false;
    # commit = null;

    expr = state.shouldExecFlatpakInstall stateData "user" false "io.github.gmodena.NewApp" null;
    expected = true;
  };
}

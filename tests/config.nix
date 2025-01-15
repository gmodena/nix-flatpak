# nix-flatpak configuration
{
  update = {
    onActivation = false;
    auto = {
      enable = false;
    };
  };
  remotes = [{ name = "some-remote"; location = "https://some.remote.tld/repo/test-remote.flatpakrepo"; }];
  packages = [{ appId = "SomeAppId"; origin = "some-remote"; }];
  overrides = { };
  uninstallUnmanaged = false;
  uninstallUnused = false;
}

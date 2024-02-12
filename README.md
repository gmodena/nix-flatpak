[![system build](https://github.com/gmodena/nix-flatpak/actions/workflows/test.yml/badge.svg)](https://github.com/gmodena/nix-flatpak/actions/workflows/test.yml)

# nix-flatpak

Declarative flatpak manager for NixOS inspired by [declarative-flatpak](https://github.com/GermanBread/declarative-flatpak) and nix-darwin's [homebrew](https://github.com/LnL7/nix-darwin/blob/master/modules/homebrew.nix) module.
NixOs and home-manager modules are provided for system wide or user flatpaks installation.

## Background

This repository contains experimental code inspired by  Martin Wimpress' [Blending NixOS with Flathub for friends and family](https://talks.nixcon.org/nixcon-2023/talk/MNUFFP/)
talk at NixCon 2023. I like the idea of managing applications the same way I do
with homebrew on nix-darwin.

`nix-flatpak` follows a [convergent mode](https://flyingcircus.io/blog/thoughts-on-systems-management-methods/) approach to package management (described in [this thread](https://discourse.nixos.org/t/feature-discussion-declarative-flatpak-configuration/26767/2)):
the target system state description is not exhaustive, and there's room for divergence across builds
and rollbacks.
For a number of desktop application I want to be able to track the latest version, or allow them to auto update.
For such applications, a convergent approach is a reasonable tradeoff wrt system reproducibility. YMMV.

Flatpak applications are installed by systemd oneshot service triggered at system activation. Depending on
the number of applications to install, this could increase activation time significantly. 

## Releases

This project is released as a [flake](https://nixos.wiki/wiki/Flakes). 
Releases are tagged with [semantic versioning](https://semver.org/). Versions below `1.0.0` are considered early, development, releases.
Users can track a version by passing its tag as `ref`
```nix
...
nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.1.0";
...
```

The `main` branch is considered unstable, and _might_ break installs.

## Getting Started

Enable flatpak in `configuration.nix`:
```nix
services.flatpak.enable = true;
```

Import the module (`nixosModules.nix-flatpak` or `homeManagerModules.nix-flatpak`).
Using flake, installing `nix-flatpak` as a NixOs module would look something like this:

```nix
{
  inputs = {
    # ...
    nix-flatpak.url = "github:gmodena/nix-flatpak"; # unstable branch. Use github:gmodena/nix-flatpak/?ref=<tag> to pin releases.
  };

  outputs = { nix-flatpak, ... }: {
    nixosConfigurations.<host> = nixpkgs.lib.nixosSystem {
      modules = [
        nix-flatpak.nixosModules.nix-flatpak

        ./configuration.nix
      ];
    };
  };
}

```

See [flake.nix](https://github.com/gmodena/nix-flatpak/blob/main/testing-base/flake.nix) in [testing-base](https://github.com/gmodena/nix-flatpak/tree/main/testing-base) for examples of setting up `nix-flatpak` as a NixOs and HomeManager module.

## Notes on HomeManager 
Depending on how config and inputs are derived `homeManagerModules` import can be flaky. Here's an example of how `homeManagerModules` is imported on my nixos systems config in [modules/home-manager/desktop/nixos/default.nix](https://github.com/gmodena/config/blob/5b3c1ce979881700f9f5ead88f2827f06143512f/modules/home-manager/desktop/nixos/default.nix#L17). `flake-inputs` is a special extra arg set in the repo `flake.nix`
[mkNixosConfiguration](https://github.com/gmodena/config/blob/5b3c1ce979881700f9f5ead88f2827f06143512f/flake.nix#L29).
 
### Remotes
By default `nix-flatpak` will add the flathub remote. Remotes can be manually
configured via the `services.flatpak.remotes` option:

```nix
services.flatpak.remotes = [{
  name = "flathub-beta"; location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
}];
```
Note that this declaration will override the default remote config value (`flathub`).
If you want to keep using `flathub`, you should explicitly declare it in the
`services.flatpak.remotes` option.

Alternatively, it is possible to merge declared remotes with the default one with `lib.mkDefaultOption`.
```nix
  services.flatpak.remotes = lib.mkOptionDefault [{
    name = "flathub-beta";
    location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
  }];
```

**Note**: currently no state management has been implemented for `remotes`.
Removing a remote for the config declaration won't delete it from the system. 
A manual `flatpak remote-delete [...]` is required. Improving remote management
is planned for future releases.

### Packages
Declare packages to install with:
```nix
  services.flatpak.packages = [
    { appId = "com.brave.Browser"; origin = "flathub";  }
    "com.obsproject.Studio"
    "im.riot.Riot"
  ];
```
You can pin a specific commit setting `commit=<hash>` attribute.

Rebuild your system (or home-manager) for changes to take place.

### Updates

Set
```nix
services.flatpak.update.onActivation = true;
```
to enable updates at system activation. The default is `false`
so that repeated invocations of `nixos-rebuild switch` are idempotent. Applications 
pinned to a specific commit hash will not be updated.

Periodic updates can be enabled  by setting:
```nix
services.flatpak.update.auto = {
  enable = true;
  onCalendar = "weekly"; # Default value
};
```
Auto updates trigger on system activation.

Under the hood, updates are scheduled by realtime systemd timers. `onCalendar` accepts systemd's
`update.auto.onCalendar` expressions. Timers are persisted across sleep / resume cycles.
See https://wiki.archlinux.org/title/systemd/Timers for more information. 

### Storage
Flatpaks are stored out of nix store at `/var/lib/flatpak` and `${HOME}/.local/share/flatpak/` for system
(`nixosModules`) and user (`homeManagerModules`) installation respectively. 
Flatpaks installation are not generational: upon a system rebuild and rollbacks, changes in packages declaration
will result in downloading applications anew.

Keeping flatpaks and nix store orthogonal is an explicit design choice, dictate by my use cases:
1. I want to track the latest version of all installed applications.
2. I am happy to trade network for storage.

YMMV.

If you need generational builds, [declarative-flatpak](https://github.com/GermanBread/declarative-flatpak)
might be a better fit.

# Known issues

A couple of things to be aware of when working with `nix-flatpak`.

## Infinte recusion in home-manager imports

Users have reported an infinite recursion stacktrace when importing an home-manager module outside of where home-manager
itself was imported.

To work around this issue, you should avoid nesting home-manager modules. This means that when you are structuring your configuration, make sure that you do not have home-manager modules imported within each other in a way that could lead to circular imports.

You can follow the discussions and updates on issue [#25](https://github.com/gmodena/nix-flatpak/issues/25) to stay informed about any resolutions or workarounds.

[![experimental](http://badges.github.io/stability-badges/dist/experimental.svg)](http://github.com/badges/stability-badges)
[![system build](https://github.com/gmodena/nix-flatpak/actions/workflows/test.yml/badge.svg)](https://github.com/gmodena/nix-flatpak/actions/workflows/test.yml)

# nix-flatpak

Declarative flatpak manager for NixOS inspired by [declarative-flatpak](https://github.com/GermanBread/declarative-flatpak) and nix-darwin's [homebrew](https://github.com/LnL7/nix-darwin/blob/master/modules/homebrew.nix) module.
NixOs and home-manager modules are provided for system wide or user flatpaks installation.

## Background

This repository contains experimental code inspired by  Martin Wimpress' [Blending NixOS with Flathub for friends and family](https://talks.nixcon.org/nixcon-2023/talk/MNUFFP/)
talk at NixCon 2023. I like the idea of managing applications the say way I do
with homebrew on nix-darwin.

`nix-flatpak` follows a [convergent mode](https://flyingcircus.io/blog/thoughts-on-systems-management-methods/) approach to package management (described in [this thread](https://discourse.nixos.org/t/feature-discussion-declarative-flatpak-configuration/26767/2)):
the target system state description is not exhaustive, and there's room for divergence across builds
and rollbacks.
For a number of desktop application I want to be able to track the lastet version, or allow them to auto update.
For such applications, a convergent approach is a reasonable tradeoff wrt system reproducibility. YMMW.

Flatpak applications are installed by systemd oneshot service triggered at system activation. Depending on
the number of applications to install, this could increase activation time significantly. 

## Getting Started

Enable flatpak in `configuration.nix`:
```nix
services.flatpak.enable = true;
```

Import the module (`nixosModules.nix-flatpak` or `homeManagerModules.nix-flatpak`).
Using flake, installing `nix-flatpak` as a NixOs module would looks something like this:

```nix
{
  inputs = {
    # ...
    nix-flatpak.url = "github:gmodena/nix-flatpak/main";
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


### Remotes
By default `nix-flatpak` will add the flathub remote. Remotes can be manually
configured via the `services.flatpak.remotes` option:

```nix
services.flatpak.remotes = [{ name = "flathub-beta"; location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo"; }];
```

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

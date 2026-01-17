# Testing base

A base GDM + Gnome `nixos` system to experiment with `nix-flatpak`. By default the flake will install NixOS 25.11 and the `nix-flatpak` module sourced from a local clone of this repo (`main` branch, unstable). Adjust `flake.nix` if you need a different setup.

The config is structured as follows
* `flake.nix` provides two outputs; one installs nix-flatpak as a home-manager module, the other a NixOS module. See the **Getting Started** session below for more details.
* `configuration.nix` contains system config (including qemu VMs specs, users, ssh etc.)
* `flatpak.nix` contains a simple [nix-flatpak](https://github.com/gmodena/nix-flatpak) configuration.

## Getting started
Build a qemu virtual machine with
```bash
nix build .#nixosConfigurations.test-system-module.config.system.build.vm
```

or 
```bash
nix build .#nixosConfigurations.test-hm-module.config.system.build.vm
```

To setup `nix-flatpak` as a nixos or a HomeManager module respectively.


Start the vm with
```bash
export QEMU_NET_OPTS="hostfwd=tcp::2221-:22"
result/bin/run-nixos-vm
```

## Login

Cerentials:
 - username: `antani`
 - password: `changeme`

Login via GDM or ssh into the vm with
```bash
ssh -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no antani@localhost -p 2221
```

Monitor the state of installed applications with:
```
flatpak list
```

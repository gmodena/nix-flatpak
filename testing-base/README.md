# Testing base

A base GDM + Gnome `nixos` system to experiment with `nix-flatpak`.

## Getting started
Build a qemu virtual machine with
```bash
nix build .#nixosConfigurations.test-system-module.config.system.build.vm
```

or 
```bash
nix build .#nixosConfigurations.test-hm-module.config.system.build.vm
```

To setup `nix-flatpak` as a nixos or HomeManager module respectively.


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

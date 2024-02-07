# Testing base

A base GDM + Gnome `nixos` system to experiment with `nix-flatpak`.

Build a qemu virtual machine with
```bash
nix build .#nixosConfigurations.test-system-module.config.system.build.vm
```

start the system with
```bash
export QEMU_NET_OPTS="hostfwd=tcp::2221-:22"
result/bin/run-nixos-vm
```

and ssh into the vm with
```bash
ssh -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no antani@localhost -p 2221
```

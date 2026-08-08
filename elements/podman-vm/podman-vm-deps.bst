kind: stack
description: |
  Minimal donate-clanker VM dependencies. FSDK's VM stack supplies the
  systemd/init, kernel, initramfs, network/DNS, certificates, and base
  filesystem contract. This stack adds only git and the pinned Go worker.
  It adds no Podman, SSH, cloud-init, or generic VM services.

depends:
- freedesktop-sdk.bst:vm/minimal/deps.bst
# The guest's init path (serial getty, donate-clanker-bootstrap.service) needs
# a shell. Until FSDK 26.08 that arrived via runtime-minimal; the userland
# split removed it, leaving a disk that builds and checksums but never reaches
# its ready point under QEMU.
- freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
- freedesktop-sdk.bst:components/git.bst
- podman-vm/donate-clanker-vm-config.bst
- podman-vm/donate-clanker-worker.bst

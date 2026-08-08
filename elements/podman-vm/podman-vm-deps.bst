kind: stack
description: |
  Minimal donate-clanker VM dependencies. FSDK's VM stack supplies the
  systemd/init, kernel, initramfs, network/DNS, certificates, and base
  filesystem contract. This stack adds only git and the pinned Go worker.
  It adds no Podman, SSH, cloud-init, or generic VM services.

depends:
- freedesktop-sdk.bst:vm/minimal/deps.bst
- freedesktop-sdk.bst:components/git.bst
- podman-vm/donate-clanker-vm-config.bst
- podman-vm/donate-clanker-worker.bst

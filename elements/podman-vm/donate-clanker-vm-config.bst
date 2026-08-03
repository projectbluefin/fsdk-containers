kind: manual
description: |
  Donate-clanker VM boot contract layered onto the full FSDK VM userspace.
  The worker executable is supplied by the pinned donate-clanker guest runtime
  input; this element owns deterministic boot, network, and channel defaults.

sources:
  - kind: local
    path: elements/podman-vm/files/donate-clanker-bootstrap.py
  - kind: local
    path: elements/podman-vm/files/donate-clanker-bootstrap.service
  - kind: local
    path: elements/podman-vm/files/donate-clanker-worker.source
  - kind: git_repo
    url: github:projectbluefin/donate-clanker.git
    ref: 5155b0bbdba0262b0ed1d948acf8d2e26b8205ce
    directory: donate-clanker

build-depends:
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  strip-binaries: ""

config:
  install-commands:
    - |
      mkdir -p "%{install-root}/etc/systemd/network"
      : > "%{install-root}/etc/machine-id"
      printf '%s\n' \
        '[Match]' \
        'Name=eth0' \
        '' \
        '[Network]' \
        'DHCP=yes' \
        > "%{install-root}/etc/systemd/network/80-donate-clanker.network"
      mkdir -p "%{install-root}/usr/libexec" \
        "%{install-root}/usr/lib/systemd/system" \
        "%{install-root}/usr/lib/systemd/system-preset" \
        "%{install-root}/etc/donate-clanker"
      install -m 0755 donate-clanker-bootstrap.py \
        "%{install-root}/usr/libexec/donate-clanker-bootstrap"
      install -m 0644 donate-clanker-bootstrap.service \
        "%{install-root}/usr/lib/systemd/system/donate-clanker-bootstrap.service"
      install -m 0644 donate-clanker/image/config/goose.yaml \
        "%{install-root}/etc/donate-clanker/goose.yaml"
      install -m 0644 donate-clanker/image/config/local-agent-policy.md \
        "%{install-root}/etc/donate-clanker/local-agent-policy.md"
      printf '%s\n' 'enable donate-clanker-bootstrap.service' \
        > "%{install-root}/usr/lib/systemd/system-preset/01-donate-clanker.preset"
      install -m 0644 donate-clanker-worker.source \
        "%{install-root}/etc/donate-clanker/worker.source"

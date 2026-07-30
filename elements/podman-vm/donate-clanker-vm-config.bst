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

build-depends:
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  strip-binaries: ""

config:
  install-commands:
    - |
      mkdir -p "%{install-root}/etc/systemd/network" "%{install-root}/sbin"
      : > "%{install-root}/etc/machine-id"
      ln -sf /usr/lib/systemd/systemd "%{install-root}/sbin/init"
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
      printf '%s\n' 'enable donate-clanker-bootstrap.service' \
        > "%{install-root}/usr/lib/systemd/system-preset/01-donate-clanker.preset"
      install -m 0644 donate-clanker-worker.source \
        "%{install-root}/etc/donate-clanker/worker.source"

kind: manual
description: |
  Donate-clanker VM boot contract layered onto the full FSDK VM userspace.
  The worker executable is supplied by the donate-clanker guest runtime
  producer; this element owns only deterministic boot and network defaults.

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

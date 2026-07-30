kind: manual
description: |
  Generic Podman VM guest defaults. Everything here is content-free of any
  user, SSH key, contributor image, or application configuration — only
  the three guest defaults a *generic* shell-enabled Podman VM needs:

  1. `podman-vm-system.preset` — re-enables `sshd.service` (FSDK's own
     `openssh.preset` disables it for desktop use by default).
  2. `podman-vm-user.preset` — enables the systemd --user `podman.socket`
     for every user session (present and future).
  3. `podman-vm-tmpfiles.conf` — pre-creates a writable, system-wide
     rootless/rootful container storage fallback location.

  See each file's own header comment for the detailed rationale. This
  element carries no build-time compilation, only `install -D`.

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ''

config:
  install-commands:
  - |
    install -Dm644 podman-vm-system.preset \
      "%{install-root}/usr/lib/systemd/system-preset/00-podman-vm.preset"
  - |
    install -Dm644 podman-vm-user.preset \
      "%{install-root}/usr/lib/systemd/user-preset/00-podman-vm.preset"
  - |
    install -Dm644 podman-vm-tmpfiles.conf \
      "%{install-root}/usr/lib/tmpfiles.d/podman-vm.conf"

sources:
- kind: local
  path: elements/podman-vm/files/podman-vm-config/podman-vm-system.preset
- kind: local
  path: elements/podman-vm/files/podman-vm-config/podman-vm-user.preset
- kind: local
  path: elements/podman-vm/files/podman-vm-config/podman-vm-tmpfiles.conf

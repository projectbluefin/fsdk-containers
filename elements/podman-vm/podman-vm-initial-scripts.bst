kind: collect_initial_scripts
description: |
  Collect every `public.initial-script` hook (BuildStream loses file
  permissions/ownership through `compose`, so components — e.g.
  `components/shadow.bst`'s `setcap cap_setuid+ep newuidmap` — ship a
  script here instead) from the full podman-vm-deps.bst transitive graph.
  Run against /sysroot by prepare-image.sh (see podman-vm-efi.bst).
  Mirrors freedesktop-sdk.bst:vm/minimal/initial-scripts.bst, scoped to
  this image's own (larger) dependency set.

build-depends:
- podman-vm/podman-vm-deps.bst

config:
  path: /etc/fdsdk/initial_scripts

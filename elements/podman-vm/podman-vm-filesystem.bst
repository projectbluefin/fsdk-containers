kind: compose
description: |
  Chisel the podman-vm-deps stack down to runtime-only content for the
  disk root partition. Debug symbols, development headers, docs, and test
  suites are stripped; the shell (bash) is intentionally KEPT — this is a
  shell-enabled VM guest filesystem, not a distroless OCI image (contrast
  with elements/base/base-runtime.bst). Mirrors
  freedesktop-sdk.bst:vm/minimal/filesystem.bst's own exclude list.

  NOTE: the `shells` exclude domain covers only `/usr/share/{fish,zsh}`
  completion data, not the `bash` binary itself (see AGENTS.md hard rule 4
  and docs/skills/nspawn-machine-image.md) — excluding it here does not
  remove the shell.

build-depends:
- podman-vm/podman-vm-deps.bst

config:
  exclude:
  - debug
  - devel
  - doc
  - tests
  - shells
  include-orphans: True

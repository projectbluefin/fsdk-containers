kind: compose
description: |
  Chisel the donate-clanker VM dependency stack to runtime-only content.
  Debug symbols, development headers, docs, tests, and shell completion data
  are excluded using the same policy as FSDK's VM filesystem.

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

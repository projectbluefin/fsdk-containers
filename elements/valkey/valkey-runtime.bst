kind: compose
description: Chisel the valkey stack down to runtime-only, distroless.

build-depends:
  - valkey/valkey-stack.bst

config:
  exclude:
    - debug
    - devel
    - doc
    - locale
    - static-blocklist
    - vm-only
    - tests
    - shells

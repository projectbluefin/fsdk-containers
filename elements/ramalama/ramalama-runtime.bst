kind: compose
description: Chisel the RamaLama stack down to runtime-only, distroless.

build-depends:
  - ramalama/ramalama-stack.bst

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

kind: compose
description: Chisel the curl stack down to runtime-only, distroless.

build-depends:
  - curl/curl-stack.bst

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

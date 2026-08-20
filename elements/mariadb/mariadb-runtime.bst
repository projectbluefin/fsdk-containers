kind: compose
description: Chisel the mariadb stack down to runtime-only, distroless.

build-depends:
  - mariadb/mariadb-stack.bst

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

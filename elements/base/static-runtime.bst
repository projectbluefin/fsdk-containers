kind: compose
description: Chisel the static stack down to runtime-only, distroless.

build-depends:
  - base/static-stack.bst

config:
  exclude:
    - debug
    - devel
    - doc
    - locale
    - extra
    - vm-only
    - tests
    - shells

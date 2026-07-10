kind: compose
description: Chisel the python stack down to runtime-only, distroless.

build-depends:
  - python/python-stack.bst

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

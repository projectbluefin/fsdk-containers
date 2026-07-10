kind: compose
description: Chisel the buildah stack down to runtime-only, distroless.

build-depends:
  - buildah/buildah-stack.bst

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

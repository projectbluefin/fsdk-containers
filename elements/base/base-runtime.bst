# DO NOT EDIT. Generated from catalog/base.yaml by
# scripts/generate_image_elements.py (compose).
# Change the record, then run: just catalog-write

kind: compose
description: Chisel the base stack down to runtime-only, distroless.

build-depends:
  - base/base-stack.bst

config:
  exclude:
    - debug
    - devel
    - doc
    - locale
    - shells
    - static-blocklist
    - tests
    - vm-only

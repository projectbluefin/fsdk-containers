# DO NOT EDIT. Generated from catalog/static.yaml by
# scripts/generate_image_elements.py (compose).
# Change the record, then run: just catalog-write

kind: compose
description: Chisel the static stack down to runtime-only, distroless.

build-depends:
  - static/static-stack.bst

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

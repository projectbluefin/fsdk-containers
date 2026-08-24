# DO NOT EDIT. Generated from catalog/python.yaml by
# scripts/generate_image_elements.py (compose).
# Change the record, then run: just catalog-write

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
    - shells
    - static-blocklist
    - tests
    - vm-only

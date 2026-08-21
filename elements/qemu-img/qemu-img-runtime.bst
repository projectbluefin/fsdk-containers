# DO NOT EDIT. Generated from catalog/qemu-img.yaml by
# scripts/generate_image_elements.py (compose).
# Change the record, then run: just catalog-write

kind: compose
description: Chisel the qemu-img stack down to runtime-only, distroless.

build-depends:
  - qemu-img/qemu-img-stack.bst

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

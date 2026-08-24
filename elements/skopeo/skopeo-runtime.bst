# DO NOT EDIT. Generated from catalog/skopeo.yaml by
# scripts/generate_image_elements.py (compose).
# Change the record, then run: just catalog-write

kind: compose
description: Chisel the skopeo stack down to runtime-only, distroless.

build-depends:
  - skopeo/skopeo-stack.bst

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

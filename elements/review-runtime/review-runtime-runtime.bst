# DO NOT EDIT. Generated from catalog/review-runtime.yaml by
# scripts/generate_image_elements.py (compose).
# Change the record, then run: just catalog-write

kind: compose
description: Chisel the review-runtime stack down to runtime-only, distroless.

build-depends:
  - review-runtime/review-runtime-stack.bst

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

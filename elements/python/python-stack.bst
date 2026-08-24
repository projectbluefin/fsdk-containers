# DO NOT EDIT. Generated from catalog/python.yaml by
# scripts/generate_image_elements.py (stack).
# Change the record, then run: just catalog-write

kind: stack
description: Distroless Python 3 image built on freedesktop-sdk

depends:
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/python3.bst

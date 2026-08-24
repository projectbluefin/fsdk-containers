# DO NOT EDIT. Generated from catalog/skopeo.yaml by
# scripts/generate_image_elements.py (stack).
# Change the record, then run: just catalog-write

kind: stack
description: Distroless skopeo image carved from freedesktop-sdk

depends:
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/skopeo.bst
  - freedesktop-sdk.bst:components/containers-common.bst
  - freedesktop-sdk.bst:components/gpgme.bst
  - freedesktop-sdk.bst:components/libassuan.bst
  - freedesktop-sdk.bst:components/sqlite.bst
  - freedesktop-sdk.bst:components/libgpg-error.bst
  - freedesktop-sdk.bst:components/glib.bst
  - freedesktop-sdk.bst:components/pkg-config.bst

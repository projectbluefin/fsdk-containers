# DO NOT EDIT. Generated from catalog/buildah.yaml by
# scripts/generate_image_elements.py (stack).
# Change the record, then run: just catalog-write

kind: stack
description: Distroless Buildah container-building tool built on freedesktop-sdk

depends:
  - base/base-stack.bst
  - buildah/buildah.bst
  - freedesktop-sdk.bst:components/containers-common.bst
  - freedesktop-sdk.bst:components/gpgme.bst
  - freedesktop-sdk.bst:components/libassuan.bst
  - freedesktop-sdk.bst:components/libgpg-error.bst
  - freedesktop-sdk.bst:components/libseccomp.bst
  - freedesktop-sdk.bst:components/glib.bst
  - freedesktop-sdk.bst:components/sqlite.bst

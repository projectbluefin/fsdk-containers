kind: stack
description: Buildah runtime stack (glibc + CA + tzdata + buildah + containers-common)

depends:
  - base/base-stack.bst
  - buildah/buildah.bst
  - freedesktop-sdk.bst:components/containers-common.bst
  - freedesktop-sdk.bst:components/gpgme.bst
  - freedesktop-sdk.bst:components/libassuan.bst
  - freedesktop-sdk.bst:components/libgpg-error.bst
  - freedesktop-sdk.bst:components/libseccomp.bst
  - freedesktop-sdk.bst:components/glib.bst

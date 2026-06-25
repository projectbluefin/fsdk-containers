kind: stack
description: |
  Skopeo runtime: base (glibc + CA + tzdata) plus skopeo and its
  container library dependencies (containers-common, gpgme, libassuan).

depends:
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/skopeo.bst
  - freedesktop-sdk.bst:components/containers-common.bst
  - freedesktop-sdk.bst:components/gpgme.bst
  - freedesktop-sdk.bst:components/libassuan.bst

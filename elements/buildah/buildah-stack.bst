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
  # buildah links libsqlite3 for its containers/storage database. It used to
  # arrive transitively; FSDK 26.08's tighter runtime closure means it must be
  # declared, or the binary fails with "libsqlite3.so.0: cannot open shared
  # object file". skopeo-stack.bst already lists it for the same reason.
  - freedesktop-sdk.bst:components/sqlite.bst

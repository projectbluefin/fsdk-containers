kind: stack
description: |
  Minimal static runtime: CA certificates and timezone data only.
  No glibc, no libc at all. For statically compiled binaries (Go
  programs compiled with CGO_ENABLED=0). Mirrors gcr.io/distroless/static.

depends:
  # The ca-certificates integration command (update-ca-trust) is a shell
  # script, and FSDK 26.08beta.2 no longer supplies /bin/sh implicitly.
  # This does not change what ships: ca-certificates already pulls p11-kit,
  # so glibc is present in this image today despite the note above.
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/ca-certificates.bst
  - freedesktop-sdk.bst:components/tzdata.bst
  - freedesktop-sdk.bst:components/os-release.bst
  - freedesktop-sdk.bst:integration/extra-fs.bst

kind: stack
description: |
  Seed for a future libc-free static tier. NOT libc-free today.

  The intent is CA certificates and timezone data only, for statically
  compiled binaries (Go with CGO_ENABLED=0), mirroring
  gcr.io/distroless/static. That is NOT what this builds: depending on
  runtime-gnu.bst pulls in full glibc, so the resulting image ships 88
  shared objects and is a byte-near-duplicate of `base` -- 15.9 MB
  compressed vs gcr.io/distroless/static's 0.7 MB. See #116.

  Nothing consumes this stack. Do not target it expecting a small or
  libc-free rootfs. Building the real thing means composing the produced
  cert bundle and zoneinfo files rather than depending on the components,
  since ca-certificates drags in p11-kit and therefore glibc.

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

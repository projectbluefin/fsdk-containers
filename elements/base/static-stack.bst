kind: stack
description: |
  Minimal distroless runtime: glibc + gcc-libs + base files, plus
  CA certificates and timezone data. No package manager. The shell is
  pulled by runtime-minimal but stripped by the `shells` compose domain
  in static-runtime.bst.

depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
  - freedesktop-sdk.bst:components/ca-certificates.bst
  - freedesktop-sdk.bst:components/tzdata.bst
  - freedesktop-sdk.bst:components/os-release.bst
  - freedesktop-sdk.bst:integration/extra-fs.bst
  - freedesktop-sdk.bst:integration/ldconfig.bst

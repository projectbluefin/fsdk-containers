kind: stack
description: |
  Minimal distroless runtime: glibc + gcc-libs + base files, plus
  CA certificates and timezone data. No package manager.
  
  Note on FSDK versions:
  - FSDK 25.08: runtime-minimal includes bash (which lives in 'runtime', not
    'shells'), so it is removed explicitly by rm -f in elements/oci/base.bst.
  - FSDK 26.08+: runtime-minimal drops bash and coreutils (moved to runtime-gnu),
    making runtime-minimal an even cleaner base for distroless images.

depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
  - freedesktop-sdk.bst:components/ca-certificates.bst
  - freedesktop-sdk.bst:components/tzdata.bst
  - freedesktop-sdk.bst:components/os-release.bst
  - freedesktop-sdk.bst:integration/extra-fs.bst
  - freedesktop-sdk.bst:integration/ldconfig.bst

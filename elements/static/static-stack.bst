# DO NOT EDIT. Generated from catalog/static.yaml by
# scripts/generate_image_elements.py (stack).
# Change the record, then run: just catalog-write

kind: stack
description: 'Static-binary runner: CA certificates, tzdata, os-release, passwd/group.
  No libc, no shell, no executables. For CGO_ENABLED=0 Go and static Rust binaries.'

# A real static tier (#116): the rootfs is data files only, matching the
# shape of gcr.io/distroless/static. runtime-gnu is staged solely so the
# ca-certificates integration command (update-ca-trust, a shell script that
# runs p11-kit) can generate the CA bundle at compose time; the slim.extra
# allowlist in the OCI element then deletes every ELF file, glibc included.
# ca-certificates cannot be composed without its p11-kit/glibc closure, so
# the tier is assembled by keeping the produced files, not by dropping the
# dependency.

depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/ca-certificates.bst
  - freedesktop-sdk.bst:components/tzdata.bst
  - freedesktop-sdk.bst:components/os-release.bst
  - freedesktop-sdk.bst:integration/extra-fs.bst

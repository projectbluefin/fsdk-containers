kind: script
description: Build the shared printing runtime as a single, reproducible OCI layer (#342).

# Publishes printing/runtime-layer.bst as a real, pullable OCI base layer --
# not a devel CAS bundle like printing-base-devel. Every printer application
# pinned to the same fsdk-containers ref produces this exact layer, so
# consumers use it as a `parent:` layer (build-oci's `parent.image` /
# `parent.index`) ahead of their own app-specific layer. Digest stability:
# `gzip: disabled` and no `created`/timestamp fields in the build-oci config,
# so two builds of the same pinned tree produce a byte-identical layer tar
# and the same digest. Consumer contract: docs/skills/printing-base.md.
build-depends:
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  - freedesktop-sdk.bst:components/oci-builder.bst
  - base/base-init-script.bst
  - filename: printing/runtime-layer.bst
    config:
      location: /layer

variables:
  (@):
    - include/slim-printing.yml
    - include/fsdk-version.yml

config:
  commands:
    - "%{slim-printing-commands}"
    - "%{slim-printing-gate-commands}"
    - |
      if [ -d /initial_scripts ]; then
        for i in /initial_scripts/*; do
          "${i}" /layer
        done
      fi
    - |
      cd "%{install-root}"
      build-oci <<EOF
      mode: oci
      gzip: disabled
      images:
      - os: linux
        architecture: "%{go-arch}"
        layer: /layer
        comment: "fsdk-containers shared printing runtime layer"
        config:
          Labels:
            'org.opencontainers.image.title': 'printing-runtime-layer'
            'org.opencontainers.image.description': 'Shared printing runtime (CUPS, cups-filters, ghostscript, PAPPL, python3, bash) that every projectbluefin printer application publishes as its first, deduplicated layer'
            'org.opencontainers.image.vendor': 'Project Bluefin'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.url': 'https://github.com/projectbluefin/fsdk-containers'
            'org.opencontainers.image.source': 'https://github.com/projectbluefin/fsdk-containers'
            'io.artifacthub.package.keywords': 'printing,cups,freedesktop-sdk,bluefin'
            'io.artifacthub.package.category': 'integration-delivery'
        index-annotations:
          'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/printing-runtime-layer:%{fsdk-version}'
      EOF

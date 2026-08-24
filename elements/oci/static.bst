# DO NOT EDIT. Generated from catalog/static.yaml by
# scripts/generate_image_elements.py (oci).
# Change the record, then run: just catalog-write

kind: script

build-depends:
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  - freedesktop-sdk.bst:components/oci-builder.bst
  - static/static-init-script.bst
  - filename: static/static-runtime.bst
    config:
      location: /layer

variables:
  (@):
    - include/slim.yml
    - include/fsdk-version.yml

config:
  commands:
    - "%{slim-distroless-commands}"
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
        comment: "fsdk-containers static image"
        config:
          Labels:
            'org.opencontainers.image.title': 'static'
            'org.opencontainers.image.description': 'Deprecated: currently identical to the base image and ships glibc. Use ghcr.io/projectbluefin/base. See issue 116.'
            'org.opencontainers.image.vendor': 'Project Bluefin'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.url': 'https://github.com/projectbluefin/fsdk-containers'
            'org.opencontainers.image.source': 'https://github.com/projectbluefin/fsdk-containers'
            'io.artifacthub.package.readme-url': 'https://raw.githubusercontent.com/projectbluefin/fsdk-containers/main/README.md'
            'io.artifacthub.package.logo-url': 'https://projectbluefin.io/logo.png'
            'io.artifacthub.package.license': 'Apache-2.0'
            'io.artifacthub.package.maintainers': '[{"name":"Project Bluefin","email":"maintainers@projectbluefin.io"}]'
            'io.artifacthub.package.keywords': 'distroless,freedesktop-sdk,bluefin,static'
            'io.artifacthub.package.category': 'integration-delivery'
        index-annotations:
          'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/static:%{fsdk-version}'
      EOF

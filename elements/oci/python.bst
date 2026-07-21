kind: script

build-depends:
  - freedesktop-sdk.bst:components/oci-builder.bst
  - base/base-init-script.bst
  - filename: python/python-runtime.bst
    config:
      location: /layer

variables:
  (@): include/slim.yml

config:
  commands:
    # --- Shared SLIM Recipe ---
    - "%{slim-distroless-commands}"
    - |
      set -eu
      L=/layer
      rm -rf "$L"/usr/lib/python*/test \
             "$L"/usr/lib/python*/*/test \
             "$L"/usr/lib/python*/*/tests \
             "$L"/usr/lib/python*/ensurepip \
             "$L"/usr/lib/python*/idlelib \
             "$L"/usr/lib/python*/tkinter \
             "$L"/usr/lib/python*/turtledemo \
             "$L"/usr/lib/python*/turtle.py \
             "$L"/usr/lib/python*/lib2to3 \
             "$L"/usr/lib/python*/pydoc_data \
             "$L"/usr/lib/python*/__phello__ \
             "$L"/usr/lib/python*/config-* \
             "$L"/usr/lib/python*/*/config-* \
             "$L"/usr/lib/python*/*.a \
             "$L"/usr/lib/python*/*/*.a

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
        comment: "fsdk-containers python image"
        config:
          Entrypoint: ['/usr/bin/python3']
          Labels:
            'org.opencontainers.image.title': 'python'
            'org.opencontainers.image.description': 'Distroless Python 3 image built on freedesktop-sdk'
            'org.opencontainers.image.vendor': 'Project Bluefin'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.url': 'https://github.com/projectbluefin/fsdk-containers'
            'org.opencontainers.image.source': 'https://github.com/projectbluefin/fsdk-containers'
            'io.artifacthub.package.readme-url': 'https://raw.githubusercontent.com/projectbluefin/fsdk-containers/main/README.md'
            'io.artifacthub.package.logo-url': 'https://projectbluefin.io/logo.png'
            'io.artifacthub.package.license': 'Apache-2.0'
            'io.artifacthub.package.maintainers': '[{"name":"Project Bluefin","email":"maintainers@projectbluefin.io"}]'
            'io.artifacthub.package.keywords': 'distroless,freedesktop-sdk,bluefin,python'
            'io.artifacthub.package.category': 'integration-delivery'
        index-annotations:
          'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/python:latest'
      EOF

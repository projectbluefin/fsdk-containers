kind: script

build-depends:
  - freedesktop-sdk.bst:components/oci-builder.bst
  - base/static-init-script.bst
  - filename: base/static-runtime.bst
    config:
      location: /layer

config:
  commands:
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
        comment: "fsdk-containers static base"
        config:
          Labels:
            'org.opencontainers.image.title': 'static'
            'org.opencontainers.image.description': 'Distroless base image carved from freedesktop-sdk'
            'org.opencontainers.image.vendor': 'Project Bluefin'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.url': 'https://github.com/projectbluefin/fsdk-containers'
            'org.opencontainers.image.source': 'https://github.com/projectbluefin/fsdk-containers'
          index-annotations:
            'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/static:latest'
      EOF

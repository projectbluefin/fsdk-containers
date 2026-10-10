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
      # Data-only allowlist: keep these paths, delete everything else (glibc,
      # p11-kit, coreutils...). A missing path fails the build rather than
      # shipping an image without CA certs or zoneinfo.
      K=/static-keep
      for p in etc/passwd etc/group etc/localtime etc/os-release \
               usr/lib/os-release usr/share/zoneinfo \
               etc/ssl/cert.pem etc/ssl/certs \
               etc/pki/tls/cert.pem etc/pki/tls/certs/ca-bundle.crt \
               etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem \
               etc/pki/ca-trust/extracted/pem/directory-hash \
               usr/share/licenses/freedesktop-sdk/tzdata \
               root tmp var/tmp; do
        if [ ! -e "/layer/$p" ] && [ ! -L "/layer/$p" ]; then
          echo "static allowlist: /$p missing from the composed layer" >&2
          exit 1
        fi
        mkdir -p "$K/$(dirname "$p")"
        cp -a "/layer/$p" "$K/$p"
      done
      rm -rf /layer/*
      cp -a "$K"/. /layer/
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
            'org.opencontainers.image.description': 'Static-binary runner: CA certificates, tzdata, os-release, passwd/group. No libc, no shell, no executables. For CGO_ENABLED=0 Go and static Rust binaries.'
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

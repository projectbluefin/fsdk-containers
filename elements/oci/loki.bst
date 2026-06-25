kind: script
description: |
  Loki log aggregation server — static binary on the fsdk-containers
  static (no-glibc) base. Mirrors the upstream distroless/static pattern.

build-depends:
  - freedesktop-sdk.bst:components/oci-builder.bst
  - static/static-init-script.bst
  - filename: static/static-runtime.bst
    config:
      location: /layer
  - filename: loki/loki-bin.bst
    config:
      location: /loki-bin

config:
  commands:
    - |
      set -eu
      L=/layer

      # Install loki binary
      # The zip unpacks to loki-linux-amd64 or loki-linux-arm64 depending on arch
      install -Dm755 /loki-bin/loki-linux-* "$L/usr/bin/loki"

      # Minimal static SLIM: no terminfo, no build tools
      rm -rf "$L"/usr/share/terminfo "$L"/usr/share/tabset \
             "$L"/etc/terminfo "$L"/lib/terminfo
      rm -f "$L"/usr/bin/localedef "$L"/usr/bin/iconvconfig

    - |
      if [ -d /initial_scripts ]; then
        for i in /initial_scripts/*; do
          "${i}" /layer
        done
      fi

    - |
      # Config dirs loki expects to find on startup
      mkdir -p /layer/etc/loki /layer/loki/rules /layer/loki/rules-temp

    - |
      cd "%{install-root}"
      build-oci <<EOF
      mode: oci
      gzip: disabled
      images:
      - os: linux
        architecture: "%{go-arch}"
        layer: /layer
        comment: "fsdk-containers loki image"
        config:
          Entrypoint: ['/usr/bin/loki']
          Cmd: ['-config.file=/etc/loki/local-config.yaml']
          ExposedPorts:
            '3100/tcp': {}
          Labels:
            'org.opencontainers.image.title': 'loki'
            'org.opencontainers.image.description': 'Loki log aggregation — static binary on fsdk-containers static base'
            'org.opencontainers.image.vendor': 'Project Bluefin'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.url': 'https://github.com/projectbluefin/fsdk-containers'
            'org.opencontainers.image.source': 'https://github.com/projectbluefin/fsdk-containers'
        index-annotations:
          'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/loki:latest'
      EOF

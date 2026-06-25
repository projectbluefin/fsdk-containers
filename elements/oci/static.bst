kind: script

build-depends:
  - freedesktop-sdk.bst:components/oci-builder.bst
  - static/static-init-script.bst
  - filename: static/static-runtime.bst
    config:
      location: /layer

config:
  commands:
    - |
      set -eu
      L=/layer

      # --- terminfo: useless in containers ---
      rm -rf "$L"/usr/share/terminfo "$L"/usr/share/tabset \
             "$L"/etc/terminfo "$L"/lib/terminfo

      # --- build-time tools leaked into runtime domain ---
      rm -f "$L"/usr/bin/localedef "$L"/usr/bin/iconvconfig

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
            'org.opencontainers.image.description': 'Distroless static image carved from freedesktop-sdk — no glibc, for statically compiled binaries'
            'org.opencontainers.image.vendor': 'Project Bluefin'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.url': 'https://github.com/projectbluefin/fsdk-containers'
            'org.opencontainers.image.source': 'https://github.com/projectbluefin/fsdk-containers'
        index-annotations:
          'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/static:latest'
      EOF

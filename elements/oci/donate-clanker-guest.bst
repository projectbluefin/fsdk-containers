kind: script

build-depends:
  - freedesktop-sdk.bst:components/oci-builder.bst
  - base/base-init-script.bst
  - filename: base/base-runtime.bst
    config:
      location: /layer

variables:
  (@): include/slim.yml

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
      mkdir -p /layer/etc/donate-clanker
      printf '%s\n' \
        '{"format":"donate-clanker-guest-rootfs-v1","rootfs":"/","kernel":"external","initramfs":"external"}' \
        > /layer/etc/donate-clanker/guest-artifact.json
    - |
      cd "%{install-root}"
      build-oci <<EOF
      mode: oci
      gzip: disabled
      images:
      - os: linux
        architecture: "%{go-arch}"
        layer: /layer
        comment: "fsdk-containers donate-clanker guest rootfs contract"
        config:
          Labels:
            'org.opencontainers.image.title': 'donate-clanker-guest'
            'org.opencontainers.image.description': 'FSDK guest rootfs first slice for donate-clanker'
            'org.opencontainers.image.vendor': 'Project Bluefin'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.source': 'https://github.com/projectbluefin/fsdk-containers'
            'io.projectbluefin.donate-clanker.artifact': 'guest-rootfs'
            'io.projectbluefin.donate-clanker.kernel': 'external'
            'io.projectbluefin.donate-clanker.initramfs': 'external'
        index-annotations:
          'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/donate-clanker-guest:latest'
      EOF

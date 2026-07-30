kind: script

build-depends:
  - freedesktop-sdk.bst:components/oci-builder.bst
  - base/base-init-script.bst
  - filename: qemu-system/qemu-system-runtime.bst
    config:
      location: /layer

variables:
  (@): include/slim.yml
  qemu-target: ""
  (?):
    - arch == "x86_64":
        qemu-target: "x86_64"
    - arch == "aarch64":
        qemu-target: "aarch64"

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
        comment: "fsdk-containers donate-clanker QEMU microVM runner"
        config:
          Entrypoint: ['/usr/bin/qemu-system-%{qemu-target}']
          Labels:
            'org.opencontainers.image.title': 'donate-clanker-vm-runner'
            'org.opencontainers.image.description': 'Headless QEMU microVM runner carved from freedesktop-sdk'
            'org.opencontainers.image.vendor': 'Project Bluefin'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.source': 'https://github.com/projectbluefin/fsdk-containers'
            'io.projectbluefin.donate-clanker.artifact': 'vm-runner'
            'io.projectbluefin.donate-clanker.architectures': 'amd64,arm64'
        index-annotations:
          'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/donate-clanker-vm-runner:latest'
      EOF

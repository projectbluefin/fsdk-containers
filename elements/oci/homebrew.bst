kind: script
description: |
  Package the Homebrew developer environment as an OCI image.

  Sibling of elements/homebrew/homebrew-nspawn.bst: both stage the SAME rootfs
  (homebrew-runtime + homebrew-prefix) and share include/homebrew-rootfs.yml.
  This one emits an OCI image for podman/docker; that one emits a rootfs
  tarball for machinectl import-tar.

  NOT distroless, deliberately. Homebrew needs a shell, a compiler toolchain,
  locale data and devel headers to build formulas from source, so the SLIM
  recipe is NOT applied here. This is the same documented exception the nspawn
  image carries -- see docs/skills/nspawn-machine-image.md. Do not "fix" this
  image by slimming it.

build-depends:
  # Root toolchain to run the assembly commands. base-stack provides /bin/sh,
  # without which the sandbox fails with "Staged artifacts do not provide
  # command 'sh'" -- see the note in elements/base/base-stack.bst. Root-staged
  # content is not part of /layer, so it never reaches the image.
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/oci-builder.bst
  - base/base-init-script.bst
  # The rootfs content, staged into /layer.
  - filename: homebrew/homebrew-runtime.bst
    config:
      location: /layer
  - filename: homebrew/homebrew-prefix.bst
    config:
      location: /layer

variables:
  (@): include/homebrew-rootfs.yml

config:
  commands:
    # --- Shared rootfs finalisation (linuxbrew user, locale) ---
    - "%{homebrew-rootfs-commands}"

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
        comment: "fsdk-containers homebrew image"
        config:
          # Interactive developer environment: a login-ish shell is the useful
          # default. Override per invocation, e.g. podman run --rm homebrew brew install jq
          Cmd: ['/usr/bin/bash']
          User: '1001:1001'
          WorkingDir: '/home/linuxbrew'
          Env:
            - 'PATH=/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/bin:/usr/sbin'
            - 'HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew'
            - 'HOMEBREW_CELLAR=/home/linuxbrew/.linuxbrew/Cellar'
            - 'HOMEBREW_REPOSITORY=/home/linuxbrew/.linuxbrew/Homebrew'
            - 'LANG=C.UTF-8'
          Labels:
            'org.opencontainers.image.title': 'homebrew'
            'org.opencontainers.image.description': 'Homebrew developer environment built on freedesktop-sdk'
            'org.opencontainers.image.vendor': 'Project Bluefin'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.url': 'https://github.com/projectbluefin/fsdk-containers'
            'org.opencontainers.image.source': 'https://github.com/projectbluefin/fsdk-containers'
            'io.artifacthub.package.readme-url': 'https://raw.githubusercontent.com/projectbluefin/fsdk-containers/main/README.md'
            'io.artifacthub.package.logo-url': 'https://projectbluefin.io/logo.png'
            'io.artifacthub.package.license': 'Apache-2.0'
            'io.artifacthub.package.maintainers': '[{"name":"Project Bluefin","email":"maintainers@projectbluefin.io"}]'
            'io.artifacthub.package.keywords': 'homebrew,brew,freedesktop-sdk,bluefin,devenv'
            'io.artifacthub.package.category': 'integration-delivery'
        index-annotations:
          'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/homebrew:latest'
      EOF

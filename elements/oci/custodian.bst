# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0

kind: script

build-depends:
  # FSDK 26.08 removed the shell from runtime-minimal, so the script
  # sandbox no longer gets /bin/sh implicitly. The SLIM recipe is a
  # shell script, so declare its interpreter explicitly.
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  - freedesktop-sdk.bst:components/oci-builder.bst
  - base/base-init-script.bst
  - filename: custodian/custodian-runtime.bst
    config:
      location: /layer

variables:
  (@):
    - include/slim.yml
    - include/fsdk-version.yml

config:
  commands:
    # --- Shared SLIM Recipe ---
    - "%{slim-distroless-commands}"

    # --- Non-root contract (#120) ---
    # Numeric 65532:65532 (matching gcr.io/distroless nonroot) PLUS an
    # /etc/passwd + /etc/group entry. The passwd entry is load-bearing for a
    # Python app: getpass.getuser()/pwd.getpwuid() raise without it. This
    # MUST happen here in the OCI script stage: REAPI discards ownership and
    # mode, so doing it in a build element silently no-ops on the grid.
    # Never write in place over a staged /etc/passwd — /layer files are
    # hardlinked from the worker's shared pool; rm -f first.
    - |
      set -eu
      L=/layer
      rm -f "$L/etc/passwd" "$L/etc/group"
      printf 'root:x:0:0:root:/root:/sbin/nologin\nnonroot:x:65532:65532:nonroot:/home/nonroot:/sbin/nologin\n' > "$L/etc/passwd"
      printf 'root:x:0:\nnonroot:x:65532:\n' > "$L/etc/group"
      mkdir -p "$L/home/nonroot"

    # --- Per-rider prune: python stdlib + c7n bloat ---
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
      # botocore ships every AWS service model twice (data/ + a docs/ tree
      # that duplicates them as .rst). Nothing at runtime reads docs/.
      rm -rf "$L"/usr/lib/python*/site-packages/botocore/docs
      # Byte-compiled caches double the on-disk cost of the .py sources.
      for d in "$L"/usr/lib/python*/site-packages/*/__pycache__ \
               "$L"/usr/lib/python*/__pycache__; do
        [ -d "$d" ] && rm -rf "$d" || true
      done

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
        comment: "fsdk-containers custodian image"
        config:
          User: '65532:65532'
          WorkingDir: '/home/nonroot'
          Entrypoint: ['/usr/bin/custodian']
          Cmd: ['--help']
          Env:
            - 'LC_ALL=C.UTF-8'
            - 'LANG=C.UTF-8'
            - 'HOME=/home/nonroot'
          Labels:
            'org.opencontainers.image.title': 'custodian'
            'org.opencontainers.image.description': 'Distroless Cloud Custodian (c7n) rules engine built on freedesktop-sdk'
            'org.opencontainers.image.vendor': 'Project Bluefin'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.url': 'https://github.com/projectbluefin/fsdk-containers'
            'org.opencontainers.image.source': 'https://github.com/projectbluefin/fsdk-containers'
            'io.artifacthub.package.readme-url': 'https://raw.githubusercontent.com/projectbluefin/fsdk-containers/main/README.md'
            'io.artifacthub.package.logo-url': 'https://projectbluefin.io/logo.png'
            'io.artifacthub.package.license': 'Apache-2.0'
            'io.artifacthub.package.maintainers': '[{"name":"Project Bluefin","email":"maintainers@projectbluefin.io"}]'
            'io.artifacthub.package.keywords': 'distroless,freedesktop-sdk,bluefin,cloud-custodian,c7n,cncf'
            'io.artifacthub.package.category': 'integration-delivery'
        index-annotations:
          'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/custodian:%{fsdk-version}'
      EOF

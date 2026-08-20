kind: manual
description: Fetch the actionlint GitHub Actions workflow linter for lab-runner

build-depends:
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  - freedesktop-sdk.bst:bootstrap/glibc.bst
  - freedesktop-sdk.bst:components/gcc-libs.bst
  - freedesktop-sdk.bst:components/tar.bst
  - freedesktop-sdk.bst:components/gzip.bst

variables:
  strip-binaries: ""
  actionlint_version: 1.7.12

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "https://github.com/rhysd/actionlint/releases/download/v%{actionlint_version}/actionlint_%{actionlint_version}_linux_amd64.tar.gz"
          ref: 8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
      - arch == "aarch64":
          url: "https://github.com/rhysd/actionlint/releases/download/v%{actionlint_version}/actionlint_%{actionlint_version}_linux_arm64.tar.gz"
          ref: 325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6

    filename: actionlint.tar.gz

config:
  install-commands:
    - |
      tar --no-same-owner -xzf actionlint.tar.gz actionlint
      mkdir -p "%{install-root}/usr/bin"
      cp actionlint "%{install-root}/usr/bin/actionlint"
      chmod 755 "%{install-root}/usr/bin/actionlint"

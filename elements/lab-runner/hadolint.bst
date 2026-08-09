kind: manual
description: Fetch the Hadolint Dockerfile/Containerfile linter for lab-runner

build-depends:
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  - freedesktop-sdk.bst:bootstrap/glibc.bst
  - freedesktop-sdk.bst:components/gcc-libs.bst

variables:
  strip-binaries: ""
  hadolint_version: v2.15.1

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "https://github.com/hadolint/hadolint/releases/download/%{hadolint_version}/hadolint-linux-x86_64"
          ref: c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507
      - arch == "aarch64":
          url: "https://github.com/hadolint/hadolint/releases/download/%{hadolint_version}/hadolint-linux-arm64"
          ref: f6198ef8090f404dbb771abfee086eb8c48ac177f30da7fd3510aca35b344b5d
    filename: hadolint

config:
  install-commands:
    - |
      mkdir -p "%{install-root}/usr/bin"
      cp hadolint "%{install-root}/usr/bin/hadolint"
      chmod 755 "%{install-root}/usr/bin/hadolint"

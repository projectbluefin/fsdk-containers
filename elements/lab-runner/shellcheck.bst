kind: manual
description: Fetch the ShellCheck shell script linter for lab-runner

build-depends:
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  - freedesktop-sdk.bst:bootstrap/glibc.bst
  - freedesktop-sdk.bst:components/gcc-libs.bst
  - freedesktop-sdk.bst:components/tar.bst
  - freedesktop-sdk.bst:components/xz.bst

variables:
  strip-binaries: ""
  shellcheck_version: v0.10.0

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "https://github.com/koalaman/shellcheck/releases/download/%{shellcheck_version}/shellcheck-%{shellcheck_version}.linux.x86_64.tar.xz"
          ref: 6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87
      - arch == "aarch64":
          url: "https://github.com/koalaman/shellcheck/releases/download/%{shellcheck_version}/shellcheck-%{shellcheck_version}.linux.aarch64.tar.xz"
          ref: 324a7e89de8fa2aed0d0c28f3dab59cf84c6d74264022c00c22af665ed1a09bb

    filename: shellcheck.tar.xz

config:
  install-commands:
    - |
      tar --no-same-owner -xf shellcheck.tar.xz --strip-components=1 "shellcheck-%{shellcheck_version}/shellcheck"
      mkdir -p "%{install-root}/usr/bin"
      cp shellcheck "%{install-root}/usr/bin/shellcheck"
      chmod 755 "%{install-root}/usr/bin/shellcheck"

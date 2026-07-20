kind: manual
description: Fetch the just command runner for lab-runner

build-depends:
  - freedesktop-sdk.bst:components/gzip.bst

variables:
  strip-binaries: ""
  # renovate: datasource=github-releases depName=casey/just
  just_version: 1.57.0

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "https://github.com/casey/just/releases/download/%{just_version}/just-%{just_version}-x86_64-unknown-linux-musl.tar.gz"
          ref: 45b548094283cb9739af8f13273b8cddeee869f5b4ef2bb631b1f311cb566155
      - arch == "aarch64":
          url: "https://github.com/casey/just/releases/download/%{just_version}/just-%{just_version}-aarch64-unknown-linux-musl.tar.gz"
          ref: f225044a81adea6e0b3a8b9370aaf374e6af76c8735ae263ac993df55fd137ec
    filename: just.tar.gz

config:
  install-commands:
    - |
      tar -xzf just.tar.gz just
      install -D -m 755 just "%{install-root}/usr/bin/just"

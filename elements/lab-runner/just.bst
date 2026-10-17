kind: manual
description: Fetch the just command runner for lab-runner

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
- freedesktop-sdk.bst:components/gzip.bst
- freedesktop-sdk.bst:components/tar.bst
- freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  strip-binaries: ""
  # renovate: datasource=github-releases depName=casey/just
  just_version: 1.59.0

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "https://github.com/casey/just/releases/download/%{just_version}/just-%{just_version}-x86_64-unknown-linux-musl.tar.gz"
      ref: 409044617b6f06517c1035e55ca38c8c856ff8b650e41bc2aa1ef82d5903a23e
  - arch == "aarch64":
      url: "https://github.com/casey/just/releases/download/%{just_version}/just-%{just_version}-aarch64-unknown-linux-musl.tar.gz"
      ref: 23871b1702bfd550fb5f901778fd4290ecf2ee034a45a889fbe96d89b188086d
  filename: just.tar.gz

config:
  install-commands:
  - |
    # --no-same-owner: the release tarball records uid/gid 1001, and
    # restoring that ownership is not permitted inside the BuildStream
    # sandbox ("Cannot change ownership to uid 1001, gid 1001"), which
    # makes tar exit non-zero even though the member extracted fine.
    tar --no-same-owner -xzf just.tar.gz just
    mkdir -p "%{install-root}/usr/bin"
    cp just "%{install-root}/usr/bin/just"
    chmod 755 "%{install-root}/usr/bin/just"

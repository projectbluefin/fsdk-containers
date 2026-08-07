kind: manual
description: Fetch the shellcheck static binary for lab-runner

build-depends:
  - freedesktop-sdk.bst:components/tar.bst
  - freedesktop-sdk.bst:components/xz.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  # Static prebuilt binary; the automatic FSDK stripper is unavailable in
  # manual-element sandboxes anyway, so just disable it.
  strip-binaries: ""
  shellcheck_version: v0.11.0

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "https://github.com/koalaman/shellcheck/releases/download/%{shellcheck_version}/shellcheck-%{shellcheck_version}.linux.x86_64.tar.xz"
          ref: 8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
      - arch == "aarch64":
          url: "https://github.com/koalaman/shellcheck/releases/download/%{shellcheck_version}/shellcheck-%{shellcheck_version}.linux.aarch64.tar.xz"
          ref: 12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588
    filename: shellcheck.tar.xz

config:
  install-commands:
    - |
      # --no-same-owner: the release tarball may record a build-machine
      # uid/gid that the sandbox cannot restore, which otherwise makes tar
      # exit non-zero even though the member extracted correctly.
      tar --no-same-owner -xJf shellcheck.tar.xz --strip-components=1 \
        "shellcheck-%{shellcheck_version}/shellcheck"
      mkdir -p "%{install-root}/usr/bin"
      cp shellcheck "%{install-root}/usr/bin/shellcheck"
      chmod 755 "%{install-root}/usr/bin/shellcheck"

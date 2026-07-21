kind: manual
description: Build bootc from offline vendored sources.

build-depends:
  - freedesktop-sdk.bst:components/rust.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/pkg-config.bst
  - freedesktop-sdk.bst:components/git-minimal.bst
  - freedesktop-sdk.bst:components/make.bst
  - freedesktop-sdk.bst:components/tar.bst
  - freedesktop-sdk.bst:components/zstd.bst

depends:
  - freedesktop-sdk.bst:components/ostree.bst
  - freedesktop-sdk.bst:components/glib.bst
  - freedesktop-sdk.bst:components/openssl.bst

sources:
  - kind: tar
    url: "https://github.com/containers/bootc/archive/refs/tags/%{bootc_version}.tar.gz"
    ref: 77b4c7114915bca1e9ea9e29f64f3c0bea7c58e0db3ce81408d81409e135b4ba
  - kind: remote
    url: "https://github.com/bootc-dev/bootc/releases/download/%{bootc_version}/bootc-%{bootc_version}-vendor.tar.zstd"
    filename: bootc-vendor.tar.zstd
    ref: b707122ce8ebc8d1a145c9122c5d1258379e42466affdd8ecaa4d6d256b9224b

variables:
  strip-binaries: ""
  # renovate: datasource=github-releases depName=containers/bootc
  bootc_version: v1.16.4

config:
  build-commands:
    - |
      tar --zstd -xf bootc-vendor.tar.zstd
      mkdir -p .cargo
      cat << 'EOF' > .cargo/config.toml
      [source.crates-io]
      replace-with = "vendored-sources"

      [source.vendored-sources]
      directory = "vendor"

      [patch."https://github.com/composefs/composefs-rs"]
      composefs-ctl = { path = "vendor/composefs-ctl" }
      EOF
      rm -rf crates/tests-integration
      cargo build --release --offline -p bootc

  install-commands:
    - |
      mkdir -p "%{install-root}/usr/bin"
      cp target/release/bootc "%{install-root}/usr/bin/bootc"

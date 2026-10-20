kind: manual
description: |
  Stage the real Homebrew Git checkout and version-matched portable Ruby as
  /usr/share/bluefin/homebrew-seed. Consumers copy this immutable seed to the
  single-owner writable canonical Linuxbrew prefix before running brew.
  The build is offline; no install.sh, interpreter download, or formulae.

sources:
- kind: git_repo
  url: github:Homebrew/brew.git
    # renovate: datasource=github-tags depName=Homebrew/brew
  track: 7.0.10
  ref: 7.0.10-0-g8f10429b56be28a25032b87463fffc95e556b5bc
  directory: brew-src
- kind: local
  path: elements/brew/files
  directory: assembly

depends:
  # coreutils + bash to run the install-commands. FSDK 26.08 removed both from
  # runtime-minimal, so name the shell stack that still provides them.
- freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
- filename: freedesktop-sdk.bst:components/git.bst
  type: build
- filename: brew/portable-ruby.bst
  type: build

variables:
  # Brew ships ruby/bash/perl scripts; nothing to strip and stripping can
  # corrupt the vendored portable-ruby shims.
  strip-binaries: ""

config:
  install-commands:
  - bash assembly/prepare-seed.sh brew-src / "%{install-root}"

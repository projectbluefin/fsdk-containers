kind: manual
description: Build buildah from source

build-depends:
# FSDK 26.08 removed the shell from runtime-minimal; these commands

# are shell scripts, so declare the interpreter explicitly.

- freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
- freedesktop-sdk.bst:components/go.bst
- freedesktop-sdk.bst:components/gcc.bst
- freedesktop-sdk.bst:components/binutils.bst
- freedesktop-sdk.bst:components/git.bst
- freedesktop-sdk.bst:components/pkg-config.bst
- freedesktop-sdk.bst:components/make.bst
- freedesktop-sdk.bst:components/sed.bst
- freedesktop-sdk.bst:components/grep.bst
- freedesktop-sdk.bst:components/diffutils.bst
- freedesktop-sdk.bst:components/gzip.bst

depends:
- freedesktop-sdk.bst:components/gpgme.bst
- freedesktop-sdk.bst:components/libassuan.bst
- freedesktop-sdk.bst:components/libgpg-error.bst
- freedesktop-sdk.bst:components/libseccomp.bst
- freedesktop-sdk.bst:components/glib.bst

variables:
  strip-binaries: ""

sources:
- kind: git_repo
  url: github:containers/buildah.git
  # renovate: datasource=github-tags depName=containers/buildah
  track: v1.45.0
  ref: b459120c69f877227039ca6ddb8131c11f6e641d

config:
  build-commands:
  - |
    make buildah PREFIX="/usr"

  install-commands:
  - |
    install -D -m 755 bin/buildah "%{install-root}/usr/bin/buildah"

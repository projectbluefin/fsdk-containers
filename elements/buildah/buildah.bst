kind: manual
description: Build buildah from source

build-depends:
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
  # renovate: datasource=github-releases depName=containers/buildah
  track: v1.36.0
  ref: v1.36.0-0-g6ceba8838d331eb26378cb37d9fc8ba98939aa92

config:
  build-commands:
    - |
      make buildah PREFIX="/usr"

  install-commands:
    - |
      install -D -m 755 bin/buildah "%{install-root}/usr/bin/buildah"

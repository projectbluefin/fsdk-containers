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
# buildah's Makefile derives its SOURCES prerequisite list with `find`;
# FSDK 26.08's tighter build userland no longer provides it implicitly.
- freedesktop-sdk.bst:components/findutils.bst
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
  track: v1.45.1
  ref: v1.45.1-0-gc8ac1936bb2e956c1d8790eba1bb3829a1241369

config:
  build-commands:
  - |
    make buildah PREFIX="/usr"

  install-commands:
  - |
    install -D -m 755 bin/buildah "%{install-root}/usr/bin/buildah"

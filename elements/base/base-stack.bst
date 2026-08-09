kind: stack
description: |
  Minimal distroless runtime: glibc + gcc-libs + base files, plus
  CA certificates and timezone data. No package manager.
  
depends:
  # FSDK 26.08beta.2 moved integration/ldconfig.bst's runtime-gnu dependency
  # from `depends:` to `build-depends:`, so a shell no longer reaches the
  # composed layer implicitly. The ca-certificates and ldconfig integration
  # commands are shell scripts and need /bin/sh staged to run at all
  # ("Staged artifacts do not provide command 'sh'"), so declare it here.
  # The SLIM recipe in include/slim.yml removes the shell from the image.
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
  - freedesktop-sdk.bst:components/ca-certificates.bst
  - freedesktop-sdk.bst:components/tzdata.bst
  - freedesktop-sdk.bst:components/os-release.bst
  - freedesktop-sdk.bst:integration/extra-fs.bst
  - freedesktop-sdk.bst:integration/ldconfig.bst

# DO NOT EDIT. Generated from catalog/base.yaml by
# scripts/generate_image_elements.py (stack).
# Change the record, then run: just catalog-write

kind: stack
description: Distroless base image carved from freedesktop-sdk

# runtime-gnu is a deliberate dependency, not an accident. FSDK 26.08beta.2
# moved integration/ldconfig.bst's runtime-gnu dependency from depends: to
# build-depends:, so a shell no longer reaches the composed layer implicitly.
# The ca-certificates and ldconfig integration commands are shell scripts and
# need /bin/sh staged to run at all. The shared SLIM recipe removes the shell
# again before the image is built.
#
# terminfo-ghostty exists because ncurses ships the entry only as "ghostty"
# while Ghostty sets TERM=xterm-ghostty (#105).

depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
  - freedesktop-sdk.bst:components/ca-certificates.bst
  - freedesktop-sdk.bst:components/tzdata.bst
  - freedesktop-sdk.bst:components/os-release.bst
  - base/terminfo-ghostty.bst
  - freedesktop-sdk.bst:integration/extra-fs.bst
  - freedesktop-sdk.bst:integration/ldconfig.bst

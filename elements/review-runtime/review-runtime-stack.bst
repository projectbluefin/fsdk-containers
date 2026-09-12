# DO NOT EDIT. Generated from catalog/review-runtime.yaml by
# scripts/generate_image_elements.py (stack).
# Change the record, then run: just catalog-write

kind: stack
description: "Distroless review appliance runtime carved from freedesktop-sdk \u2014\
  \ python3, node, bash, git, curl"

depends:
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/python3.bst
  - node/node-stack.bst
  - freedesktop-sdk.bst:components/git.bst
  - freedesktop-sdk.bst:components/curl.bst
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:components/diffutils.bst
  - freedesktop-sdk.bst:components/findutils.bst
  - freedesktop-sdk.bst:components/gawk.bst
  - freedesktop-sdk.bst:components/gzip.bst
  - freedesktop-sdk.bst:components/less.bst
  - freedesktop-sdk.bst:components/sed.bst
  - freedesktop-sdk.bst:components/tar.bst

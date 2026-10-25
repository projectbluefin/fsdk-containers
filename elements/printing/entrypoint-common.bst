kind: manual
description: Shared bash startup contract for the four printer applications.

sources:
- kind: local
  path: elements/printing/files/entrypoint-common.sh

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
- freedesktop-sdk.bst:bootstrap/bash.bst
- freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  strip-binaries: ""

config:
  install-commands:
  - install -Dm0644 entrypoint-common.sh "%{install-root}/usr/libexec/printer-app/entrypoint-common.sh"

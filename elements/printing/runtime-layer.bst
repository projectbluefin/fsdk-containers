kind: compose
description: Chisel the shared printing runtime stack down to runtime-only.

# Runtime-only slice of printing/runtime-stack.bst: no headers, .pc files,
# static archives, debug info, or test suites. `locale` is deliberately kept
# -- NOT excluded -- because gutenprint ships translated PPDs under
# usr/share/locale and the printer applications' consumer contract keeps that
# domain (docs/skills/printing-base.md). oci/printing-runtime-layer.bst
# stages this at /layer, applies the shared include/slim-printing.yml recipe,
# and publishes the result as the shared base layer (#342).
build-depends:
  - printing/runtime-stack.bst

config:
  exclude:
    - debug
    - devel
    - doc
    - shells
    - static-blocklist
    - tests
    - vm-only

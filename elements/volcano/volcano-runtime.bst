kind: compose
description: Chisel the volcano stack down to runtime-only, distroless.

build-depends:
  - volcano/volcano-stack.bst

config:
  exclude:
    - debug
    - devel
    - doc
    - locale
    - static-blocklist
    - vm-only
    - tests
    # 'shells' does not cover the bash binary; the SLIM recipe in the OCI
    # stage removes it explicitly (see elements/oci/base.bst).
    - shells

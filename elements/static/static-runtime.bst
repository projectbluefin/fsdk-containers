kind: compose
description: |
  Chisel the static stack to runtime-only. Despite the tier's name this
  does NOT remove glibc: the `debug`/`devel`/`doc` split domains do not
  cover the C runtime, which lives in the runtime domain. See #116.

build-depends:
  - static/static-stack.bst

config:
  exclude:
    - debug
    - devel
    - doc
    - locale
    - static-blocklist
    - vm-only
    - tests
    - shells

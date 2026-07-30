kind: compose
description: Chisel the donate-clanker QEMU runner to runtime-only.

build-depends:
  - qemu-system/qemu-system-stack.bst

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

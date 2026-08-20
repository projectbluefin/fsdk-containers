kind: compose
description: Chisel the node stack down to runtime-only, distroless.

build-depends:
  - node/node-stack.bst

config:
  exclude:
    - debug
    - devel
    - doc
    - locale
    - static-blocklist
    - vm-only
    - tests
    # NOTE: 'shells' covers only /usr/share/fish and /usr/share/zsh data dirs.
    # The bash binary lives in the 'runtime' domain; the SLIM recipe's
    # explicit rm -f in the OCI element does the actual shell removal.
    - shells

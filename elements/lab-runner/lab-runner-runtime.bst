# DO NOT EDIT. Generated from catalog/lab-runner.yaml by
# scripts/generate_image_elements.py (compose).
# Change the record, then run: just catalog-write

kind: compose
description: Chisel the lab-runner stack down to its runtime contract.

build-depends:
  - lab-runner/lab-runner-stack.bst

config:
  exclude:
    - debug
    - devel
    - doc
    - locale
    - static-blocklist
    - tests
    - vm-only
    # NOT excluded -- shells: lab-runner is the documented shell-enabled exception, so the fish and zsh data directories in the shells domain are harmless and excluding them buys nothing. Declared rather than silently divergent.

# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# Chisel the custodian stack down to runtime-only, distroless.
# The exclude list mirrors python/python-runtime.bst.

kind: compose

build-depends:
  - custodian/custodian-stack.bst

config:
  exclude:
    - debug
    - devel
    - doc
    - locale
    - static-blocklist
    - vm-only
    - tests
    # NOTE: 'shells' does NOT cover the bash binary (it is in the runtime
    # split domain). Bash is removed by the SLIM recipe in oci/custodian.bst.
    - shells

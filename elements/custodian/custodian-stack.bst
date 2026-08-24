# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# The custodian dependency stack: the shared base runtime (glibc, CA certs,
# tzdata) plus the c7n source-build element, which drags in the python3
# interpreter and c7n's full runtime closure.

kind: stack

depends:
  - base/base-stack.bst
  - custodian/c7n.bst

# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# typing-extensions: runtime backports required by referencing and rpds-py.
# FSDK ships python3-typing-extensions as a build-oriented component; this is
# the runtime-pinned copy for the custodian tree (kept separate so the
# rider tree owns its own pins — see docs/skills/python-rider.md).

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-flit.bst

depends:
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:f6/cc/6253133b5bb138fc3306cebfbda2c520f545d36b5be2c7255cc528bb45d6/typing_extensions-4.16.0.tar.gz
    ref: dc983d19a509c94dba722ee6abd33940f7c05a89e243c47e907eb4db6f1a43e5

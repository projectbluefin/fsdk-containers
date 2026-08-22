# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# referencing: JSON-Schema reference resolution (jsonschema dependency).

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-hatchling.bst

depends:
  - custodian/python3-rpds-py.bst
  - custodian/python3-typing-extensions.bst
  - freedesktop-sdk.bst:components/python3-attrs.bst
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/r/referencing/referencing-0.37.0.tar.gz
    ref: 44aefc3142c5b842538163acb373e24cce6632bd54bdb01b21ad5863489f50d8

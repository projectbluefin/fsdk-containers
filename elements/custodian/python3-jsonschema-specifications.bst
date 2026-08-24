# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# jsonschema-specifications: the JSON Schema spec documents (jsonschema dep).

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-hatchling.bst

depends:
  - custodian/python3-referencing.bst
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/j/jsonschema-specifications/jsonschema_specifications-2025.9.1.tar.gz
    ref: b540987f239e745613c7a9176f3edb72b832a4ac465cf02712288397832b5e8d

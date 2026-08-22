# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# jsonschema: custodian's policy-file validator.

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-hatchling.bst

depends:
  - custodian/python3-jsonschema-specifications.bst
  - custodian/python3-referencing.bst
  - custodian/python3-rpds-py.bst
  - custodian/python3-typing-extensions.bst
  - freedesktop-sdk.bst:components/python3-attrs.bst
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/j/jsonschema/jsonschema-4.26.0.tar.gz
    ref: 0c26707e2efad8aa1bfc5b7ce170f3fccc2e4918ff85989ba9ffa9facb2be326

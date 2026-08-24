# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# JMESPath: JSON query language used by botocore response shaping and by
# custodian's policy filters.

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-setuptools.bst

depends:
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/j/jmespath/jmespath-1.1.0.tar.gz
    ref: 472c87d80f36026ae83c6ddd0f1d05d4e510134ed462851fd5f754c8c3cbb88d

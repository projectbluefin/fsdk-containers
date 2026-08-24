# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# argcomplete: shell completion hooks for the custodian CLI.

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-hatchling.bst

depends:
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/a/argcomplete/argcomplete-3.6.3.tar.gz
    ref: 62e8ed4fd6a45864acc8235409461b72c9a28ee785a2011cc5eb78318786c89c

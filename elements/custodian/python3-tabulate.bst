# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# tabulate: CLI table rendering for custodian output.

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-setuptools.bst
  # Declared in the sdist's [build-system] requires (build-time only;
  # setuptools-scm derives the version from the PKG-INFO metadata).
  - custodian/python3-setuptools-scm.bst

depends:
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/t/tabulate/tabulate-0.10.0.tar.gz
    ref: e2cfde8f79420f6deeffdeda9aaec3b6bc5abce947655d17ac662b126e48a60d

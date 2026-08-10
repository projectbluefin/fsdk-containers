# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pure-python runtime dependency of python-dateutil (c7n dependency tree).
# See docs/skills/python-rider.md for the pattern every element here follows.

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-setuptools.bst

depends:
  - freedesktop-sdk.bst:components/python3.bst

variables:
  # Nothing compiled; the FSDK stripper is not useful here.
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/s/six/six-1.17.0.tar.gz
    ref: ff70335d468e7eb6ec65b95b99d3a2836546063f63acc5171de367e834932a81

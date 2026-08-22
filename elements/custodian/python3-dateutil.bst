# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# python-dateutil, required by botocore (c7n dependency tree).

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-setuptools.bst
  # Declared in the sdist's [build-system] requires (build-time only;
  # setuptools-scm derives the version from the PKG-INFO metadata).
  - custodian/python3-setuptools-scm.bst

depends:
  - custodian/python3-six.bst
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/p/python-dateutil/python-dateutil-2.9.0.post0.tar.gz
    ref: 37dd54208da7e1cd875388217d5e00ebd4179249f90fb72437e91a35459a0ad3

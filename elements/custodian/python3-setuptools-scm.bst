# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# setuptools-scm 7.x, BUILD-TIME ONLY. python-dateutil's pyproject pins
# `setuptools_scm<8.0` in [build-system].requires, but FSDK's
# components/python3-setuptools-scm.bst is 10.x and --no-isolation enforces
# the pin, so the FSDK component cannot build it. This is a rider-local,
# pinned copy staged over it for the build sandbox; nothing from this element
# ships in the runtime image.

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-setuptools.bst
  - freedesktop-sdk.bst:components/python3-packaging.bst

depends:
  - freedesktop-sdk.bst:components/python3-packaging.bst
  - freedesktop-sdk.bst:components/python3-typing-extensions.bst
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:98/12/2c1e579bb968759fc512391473340d0661b1a8c96a59fb7c65b02eec1321/setuptools_scm-7.1.0.tar.gz
    ref: 6c508345a771aad7d56ebff0e70628bf2b0ec7573762be9960214730de278f27

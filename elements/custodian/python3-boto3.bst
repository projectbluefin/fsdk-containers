# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# boto3: the AWS SDK for Python, pinned exactly as c7n pins it.

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-setuptools.bst

depends:
  - custodian/python3-botocore.bst
  - custodian/python3-jmespath.bst
  - custodian/python3-s3transfer.bst
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/b/boto3/boto3-1.43.3.tar.gz
    ref: 7c7777862ffc898f05efa566032bbabfe226dbb810e35ec11125817f128bc5c5

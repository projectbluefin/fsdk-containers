# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# s3transfer: boto3's S3 transfer manager.

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-setuptools.bst

depends:
  - custodian/python3-botocore.bst
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/s/s3transfer/s3transfer-0.19.2.tar.gz
    ref: ba0309fd86be3c27dbf78cdd813c13c5e1df16e5874b99d2535ebbdfb9892993

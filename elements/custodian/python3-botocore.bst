# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# botocore: the AWS SDK core. Version-pinned to match boto3 (AWS ships the
# pair in lockstep; c7n pins boto3==1.43.3, whose requirement is
# botocore>=1.43.3,<1.44.0).

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-setuptools.bst

depends:
  - custodian/python3-dateutil.bst
  - custodian/python3-jmespath.bst
  - freedesktop-sdk.bst:components/python3-urllib3.bst
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/b/botocore/botocore-1.43.3.tar.gz
    ref: eac6da0fffccf87888ebf4d89f0b2378218a707efa748cd955b838995e944695

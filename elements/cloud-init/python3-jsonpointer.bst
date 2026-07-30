kind: manual
description: |
  jsonpointer, a runtime dependency of jsonpatch (required by cloud-init's
  cloud-config merge handler). Not packaged by FSDK.

  Upstream ships only a legacy `setup.py` (no `pyproject.toml`); `python -m
  build` still handles this via setuptools' implicit legacy backend, so no
  extra bootstrapping is required beyond setuptools/wheel/build/installer,
  all of which FSDK already provides.

sources:
- kind: git_repo
  url: github:stefankoegl/python-json-pointer.git
  track: "v*"
  ref: v3.1.1-0-gada0cade3bcd21d5726dd701d092c7d0d1ce8c41
build-depends:
- freedesktop-sdk.bst:components/python3.bst
- freedesktop-sdk.bst:components/python3-build.bst
- freedesktop-sdk.bst:components/python3-installer.bst
- freedesktop-sdk.bst:components/python3-setuptools.bst
- freedesktop-sdk.bst:components/python3-wheel.bst

runtime-depends:
- freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ''
  dist-dir: '%{build-root}/dist'

config:
  build-commands:
  - |
    python3 -P -m build --no-isolation --wheel --outdir %{dist-dir} .

  install-commands:
  - |
    python3 -P -m installer %{dist-dir}/*.whl --destdir %{install-root}

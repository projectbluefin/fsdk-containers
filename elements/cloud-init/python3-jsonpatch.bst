kind: manual
description: |
  jsonpatch, a mandatory runtime dependency of cloud-init: it is imported
  unconditionally by cloudinit/handlers/cloud_config.py, which is loaded by
  cloudinit/stages.py on every cloud-init invocation (init/config/final).
  Not packaged by FSDK, so it is built here from upstream source.

  Upstream ships only a legacy `setup.py` (no `pyproject.toml`); `python -m
  build` still handles this via setuptools' implicit legacy backend, so no
  extra bootstrapping is required beyond setuptools/wheel/build/installer,
  all of which FSDK already provides.

sources:
- kind: git_repo
  url: github:stefankoegl/python-json-patch.git
  track: "v*"
  ref: v1.33-0-g0b0520328504050ee09d835d4df294838e055c38
build-depends:
- freedesktop-sdk.bst:components/python3.bst
- freedesktop-sdk.bst:components/python3-build.bst
- freedesktop-sdk.bst:components/python3-installer.bst
- freedesktop-sdk.bst:components/python3-setuptools.bst
- freedesktop-sdk.bst:components/python3-wheel.bst

runtime-depends:
- freedesktop-sdk.bst:components/python3.bst
- cloud-init/python3-jsonpointer.bst

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

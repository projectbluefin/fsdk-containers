kind: manual
description: |
  ConfigObj, a mandatory runtime dependency of cloud-init: cloud-init's
  module loader (`cloudinit/config/modules.py:_fixup_modules`) imports
  *every* module listed in `cloud_config_modules`/`cloud_final_modules`
  unconditionally, before the per-module `_is_active()` activation check
  runs. `cc_mcollective.py` (unconditionally listed in every variant's
  `cloud_final_modules`) and `cc_landscape.py` (listed for the
  debian/ubuntu/unknown variants) both hard-import `from configobj import
  ConfigObj` at module level, so a missing configobj breaks cloud-init's
  final stage entirely on every boot, not just the landscape/mcollective
  features — see docs/skills/add-fsdk-component.md for the full writeup of
  why this was originally (incorrectly) assumed unnecessary.

  Not packaged by FSDK, so it is built here from upstream source. Upstream
  ships both a `pyproject.toml` (setuptools.build_meta backend) and a
  legacy `setup.py`; either is handled by `python -m build`, so no extra
  bootstrapping is required beyond setuptools/wheel/build/installer, all of
  which FSDK already provides. ConfigObj itself has zero runtime
  dependencies of its own (no `install_requires`).

sources:
- kind: git_repo
  url: github:DiffSK/configobj.git
  track: "v*"
  ref: v5.0.9-0-g242dfd09510e937574758da76ddc644b71f8cc4f
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

# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# c7n: the Cloud Custodian rules engine.
#
# PyPI publishes c7n as a WHEEL ONLY (no sdist since ~0.9.45), so this element
# stages the upstream wheel and installs it with FSDK's `python3-installer` —
# the same installer the pyproject buildsystem uses — rather than `pip` (which
# would reach for the network). The wheel is pure-python (py3-none-any), so
# there is nothing to compile and no arch skew between x86_64 and aarch64.

kind: manual

build-depends:
  # The install commands are shell scripts; FSDK 26.08 removed the shell from
  # runtime-minimal, so declare the interpreter explicitly.
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  - freedesktop-sdk.bst:components/python3.bst
  - freedesktop-sdk.bst:components/python3-installer.bst

depends:
  # Runtime closure, matching c7n 0.9.51's pinned requires_dist:
  #   argcomplete boto3 cryptography jsonschema python-dateutil pyyaml
  #   tabulate urllib3
  # cryptography and pyyaml ship compiled extensions; the FSDK components are
  # reused (49.0.0 / 6.0.3 — both satisfy c7n's pins). Everything pure-python
  # that FSDK does not carry is built from its PyPI sdist in this directory.
  - custodian/python3-argcomplete.bst
  - custodian/python3-boto3.bst
  - custodian/python3-dateutil.bst
  - custodian/python3-jsonschema.bst
  - custodian/python3-tabulate.bst
  - freedesktop-sdk.bst:components/python3-cryptography.bst
  - freedesktop-sdk.bst:components/python3-pyyaml.bst
  - freedesktop-sdk.bst:components/python3-urllib3.bst
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  # PyPI wheels live at content-addressed paths; the bst-plugins-community
  # `pypi` source only zip-stages a literal `.zip` suffix (its TarStager
  # chokes on `.whl`), so fetch the wheel as a plain zip from its canonical
  # files.pythonhosted.org URL. sha256-pinned, like every other remote
  # source in this repo.
  - kind: zip
    url: pypi:57/42/7de9cee3a0b27c742f6ead8d59f61abe15a5c0f22c5e02de3826be1e3c1c/c7n-0.9.51-py3-none-any.whl
    ref: 0316ec3813fc72d48c6487ca12caf1cd8542799ebcf8d03548a297b710be6b88

config:
  install-commands:
    # FSDK's bundled `installer` (files/python-bootstrap/installer.py) unpacks
    # the wheel, generates console scripts with a `#!{sys.executable}`
    # shebang, and byte-compiles the tree. In the bst sandbox sys.executable
    # is /usr/bin/python3, which is also where python3 lands in the image.
    - |
      python3 -P -minstaller c7n-0.9.51-py3-none-any.whl --destdir "%{install-root}"

# SPDX-FileCopyrightText: Project Bluefin contributors
# SPDX-License-Identifier: Apache-2.0
#
# rpds-py: Rust-backed persistent data structures (jsonschema dependency).
# Builds the Rust extension with maturin; the Cargo.lock from the sdist is
# vendored via the cargo2 source so the build is fully offline and pinned.

kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-maturin.bst

depends:
  - custodian/python3-typing-extensions.bst
  - freedesktop-sdk.bst:components/python3.bst

variables:
  # The plugin runs %{python} -mbuild from %{build-root}; cargo2 vendors its
  # crates into the build root, so land the sdist in a subdirectory and cd in.
  build-args-local: rpds_py

  # The FSDK stripper is not usable in this minimal sandbox; the OCI layer
  # prune keeps the image slim instead.
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/r/rpds-py/rpds_py-2026.6.3.tar.gz
    ref: 1cebd1337c242e4ec2293e541f712b2da849b29f48f0c293684b71c0632625d4
    directory: rpds_py
  # Vendored crates from rpds_py/Cargo.lock (2026.6.3). The cargo2 source
  # downloads + verifies each crate and sets CARGO_HOME offline config.
  # `url` points at the repo-local `crates:` alias (same shape as FSDK's own
  # include/_private/cargo2.yml) so the source is not flagged unaliased.
  - kind: cargo2
    url: "crates:crates/"
    cargo-lock: rpds_py/Cargo.lock
    ref:
      - kind: registry
        name: archery
        version: 1.2.2
        sha: 70e0a5f99dfebb87bb342d0f53bb92c81842e100bbb915223e38349580e5441d
      - kind: registry
        name: heck
        version: 0.5.0
        sha: 2304e00983f87ffb38b55b444b5e3b60a884b5d30c0fca7d82fe33449bbe55ea
      - kind: registry
        name: libc
        version: 0.2.177
        sha: 2874a2af47a2325c2001a6e6fad9b16a53b802102b528163885171cf92b15976
      - kind: registry
        name: once_cell
        version: 1.21.3
        sha: 42f5e15c9953c5e4ccceeb2e7382a716482c34515315f7b03532b8b4e8393d2d
      - kind: registry
        name: portable-atomic
        version: 1.11.1
        sha: f84267b20a16ea918e43c6a88433c2d54fa145c92a811b5b047ccbe153674483
      - kind: registry
        name: proc-macro2
        version: 1.0.103
        sha: 5ee95bc4ef87b8d5ba32e8b7714ccc834865276eab0aed5c9958d00ec45f49e8
      - kind: registry
        name: pyo3
        version: 0.29.0
        sha: cd274650b21d4bfc26a0a47587962c1edb425f69287324355cd040c3ea66071c
      - kind: registry
        name: pyo3-build-config
        version: 0.29.0
        sha: c5e2a7d2f0d013342f295c048ad19237add5154a55b1c5a254c0ec93d4109078
      - kind: registry
        name: pyo3-ffi
        version: 0.29.0
        sha: ca85c467da1bbc8d866eea5deff9cf29ea5f7785054a17da36e65bda9c05845b
      - kind: registry
        name: pyo3-macros
        version: 0.29.0
        sha: 9ac53762fd065daa3194dd09337a38bd793a188100fd1a9304c4ab312d901771
      - kind: registry
        name: pyo3-macros-backend
        version: 0.29.0
        sha: 4ca3a1557399783172dc5bf39cfca835157732532cba56b71d2292161e53b362
      - kind: registry
        name: quote
        version: 1.0.42
        sha: a338cc41d27e6cc6dce6cefc13a0729dfbb81c262b1f519331575dd80ef3067f
      - kind: registry
        name: rpds
        version: 1.2.1
        sha: e025feb26210bc196b908e72deb063b1b4000754304341cbc168a1e72c857ebc
      - kind: registry
        name: smallvec
        version: 1.15.1
        sha: 67b1b7a3b5fe4f1376887184045fcf45c69e92af734b7aaddc05fb777b6fbd03
      - kind: registry
        name: syn
        version: 2.0.111
        sha: 390cc9a294ab71bdb1aa2e99d13be9c753cd2d7bd6560c77118597410c4d2e87
      - kind: registry
        name: target-lexicon
        version: 0.13.3
        sha: df7f62577c25e07834649fc3b39fafdc597c0a3527dc1c60129201ccfcbaa50c
      - kind: registry
        name: triomphe
        version: 0.1.15
        sha: dd69c5aa8f924c7519d6372789a74eac5b94fb0f8fcf0d4a97eb0bfc3e785f39
      - kind: registry
        name: unicode-ident
        version: 1.0.22
        sha: 9312f7c4f6ff9069b165498234ce8be658059c6728633667c526e27dc2cf1df5

---
name: offline-python-packaging
version: "1.0"
last_updated: 2026-09-20
id: offline-python-packaging
one_line_purpose: Build Python distributions offline with the pyproject element — no pip, deps declared by hand.
entry_point: docs/skills/offline-python-packaging.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: [remote-execution, add-new-image, verify-distroless]
tags: [python, pyproject, cargo2, pypi, offline, source-plugin, catalog]
description: "Recipe for the buildstream-plugins-community pyproject element: element shape, sha256 refs from PyPI, the FSDK-first dependency rule, the build-args-local trap, wheel-only upstreams via the core remote source, and Rust extensions via cargo2."
metadata:
  type: procedure
---

# Building Python distributions offline with `pyproject`

Use when an element must build a Python distribution FSDK does not already
ship — a Python application image, or one of its dependencies.

Status: the element shape below is proven — `botocore` (8m19s), `boto3`,
`s3transfer` and `dateutil` built green on the ghost grid under #123. The
`rpds-py` fix and the wheel-only recipe are **diagnosed from the pinned plugin
sources, not yet build-proven**; both are flagged inline, so do not restate
them as measured.

## The constraint that shapes everything

The build phase has no network ([`remote-execution.md`](remote-execution.md)),
so `pip install` is unavailable and **there is no dependency resolver at all**.
You declare the transitive closure yourself, one element per distribution —
the per-image cost issue #113 exists to drive down, not overhead you can skip.

`pyproject` (registered in `project.conf` from
`plugins/buildstream-plugins-community.bst`) builds an sdist with
`python -mbuild --no-isolation --wheel` and installs the result with
`python -minstaller`. It is FSDK's own answer too: all 109
`components/python3-*.bst` in FSDK 26.08.1 use this element kind.

## Check FSDK first — it already ships 109 of these

Before writing any dependency element, prove FSDK does not have it
(`just bst show freedesktop-sdk.bst:components/python3-urllib3.bst`).
Measured on the Cloud Custodian dependency tree (#123): of 14 hand-written
`python3-*` elements, `python3-typing-extensions` and `python3-setuptools-scm`
already existed as FSDK components — two elements of avoidable work, found
only after they were written. Check the whole closure in one pass first.

## Element shape

```yaml
kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-setuptools.bst

depends:
  - custodian/python3-dateutil.bst
  - freedesktop-sdk.bst:components/python3-urllib3.bst
  - freedesktop-sdk.bst:components/python3.bst

variables:
  strip-binaries: ""

sources:
  - kind: tar
    url: pypi:source/b/botocore/botocore-1.43.3.tar.gz
    ref: eac6da0fffccf87888ebf4d89f0b2378218a707efa748cd955b838995e944695
```

- `build-depends` is the build backend, `depends` the runtime closure. Match
  the stack to the upstream's `build-system.requires`: FSDK 26.08.1 publishes
  `public-stacks/buildsystem-python-{setuptools,hatchling,flit,poetry,maturin}.bst`,
  each already pulling the `python3-build` + `python3-installer` the plugin invokes.
- `strip-binaries: ""` is not cargo-culting — FSDK's own `python3-*.bst` set
  it, and the OCI layer prune keeps the image slim instead
  ([`slim-an-image.md`](slim-an-image.md)).

## Refs are PyPI sha256 sums, filled by hand

`kind: tar` against a fixed URL has nothing to track, so `bst source track`
will not fill the ref. It is the sdist's sha256, which PyPI publishes:

```bash
curl -s https://pypi.org/pypi/botocore/1.43.3/json | python3 -c \
 'import json,sys;[print(f["filename"],f["digests"]["sha256"]) for f in json.load(sys.stdin)["urls"] if f["packagetype"]=="sdist"]'
```

Use the `pypi:` alias with the readable legacy path files.pythonhosted.org
still serves — `source/<initial>/<name>/<file>` for an sdist,
`<python-tag>/<initial>/<name>/<file>` for a wheel (`py3/c/c7n/…`; wheels are
**not** under `source/`, that path 404s). Do not paste the hashed CDN path
from the JSON `url` field: it adds no integrity the `ref` does not already
give, and it is unreadable in review.

## Trap: `build-args-local` is not a subdirectory knob

The plugin's defaults (`elements/pyproject.yaml`, community 2.3.1) are:

```yaml
build-args: "--no-isolation --wheel --outdir %{dist-dir} %{build-args-local}"
dist-dir: "%{build-root}/dist"
```

and the build command is `%{python} -mbuild %{build-args} .` — it already ends
in a literal `.`. Setting `build-args-local: <subdir>` to "build from a
subdirectory" therefore hands **two** positionals to a parser that accepts one
`[srcdir]`, and the build dies in about four seconds with
`python -m build: error: unrecognized arguments: .`.

Use BuildStream's core `command-subdir` (`variables: {command-subdir: rpds_py}`)
instead. `BuildElement` sets the working directory to
`%{build-root}/%{command-subdir}`, so the `.` resolves correctly, and both
`%{dist-dir}` and `%{install-root}` are absolute — the wheel output and the
install step are unaffected.

*Diagnosed from the pinned plugin source against the #123 CI failure; not yet
build-proven.*

## Wheel-only upstreams: core `remote`, not `zip`

Some upstreams publish a wheel and no sdist at all (`c7n` since ~0.9.45).
There is nothing to build, only to install: stage the wheel **file** with
BuildStream's core `remote` source — no plugin registration needed — and hand
it to FSDK's `installer`.

```yaml
kind: manual

build-depends:
  # FSDK 26.08 removed the shell from runtime-minimal, and install-commands
  # are shell scripts, so declare bash and coreutils explicitly.
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  - freedesktop-sdk.bst:components/python3.bst
  - freedesktop-sdk.bst:components/python3-installer.bst

sources:
  - kind: remote
    url: pypi:py3/c/c7n/c7n-0.9.52-py3-none-any.whl
    ref: bbd654ee49fb9a425acbb986e23121660603bd68ce388c14b2a946ed87078e09

config:
  install-commands:
    - python3 -P -minstaller c7n-0.9.52-py3-none-any.whl --destdir "%{install-root}"
```

The community `zip` source is the wrong tool here and is deliberately not
registered: it unpacks on stage, so the `.whl` file `installer` needs no
longer exists, and its `base-dir: '*'` default cannot resolve a wheel's two
top-level entries (`<pkg>/`, `<pkg>-<ver>.dist-info/`) anyway.

*Diagnosed from the core and community source; not yet build-proven.*

## Rust extensions: `cargo2`

A Python package with a compiled Rust extension (`rpds-py`, via `jsonschema`)
cannot build offline without vendored crates. Copy the shape of FSDK's own
`components/python3-maturin.bst`:

```yaml
kind: pyproject

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-python-maturin.bst

depends:
  - freedesktop-sdk.bst:components/python3.bst
  - freedesktop-sdk.bst:components/rust.bst   # the maturin stack does NOT pull it

sources:
  - kind: tar
    url: pypi:source/r/rpds-py/rpds_py-2026.6.3.tar.gz
    ref: <sha256>
    directory: rpds_py
  - kind: cargo2
    url: "crates:crates/"
    cargo-lock: rpds_py/Cargo.lock
    ref:
      # one {kind: registry, name, version, sha} entry per crate in
      # Cargo.lock — `just bst source track <element>` fills them all in
```

- `url: "crates:crates/"` matches FSDK's `include/_private/cargo2.yml`
  verbatim (cargo2 appends `<crate>/<crate>-<version>.crate`), and
  `include/aliases.yml` defines `crates:` with the same value FSDK uses, so a
  crate mirror configured for FSDK works here unchanged.
- **Do not give the `cargo2` source a `directory:`.** It writes
  `.vendored-crates/` and `.cargo/config.toml` at the root of the staging
  tree, and the config's `directory:` key is relative. Cargo finds the config
  by walking *up* from the working directory, so root-level vendoring plus
  `command-subdir` works; moving it under the sdist directory breaks it.

## Measuring the result

`just verify` gates **uncompressed local** podman size; upstream comparison
tables are **compressed registry** size. The two are not interchangeable (see
[`verify-distroless.md`](verify-distroless.md)) — state the basis with every
number, and benchmark against upstream `-slim` variants, never `:latest`.

---
name: add-fsdk-component
version: "1.1"
last_updated: 2026-08-20
id: add-fsdk-component
one_line_purpose: Add an FSDK component and stack element without building an OCI image.
entry_point: docs/skills/add-fsdk-component/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [buildstream, fsdk, elements, components]
description: "Add a component + stack element (no OCI image) composed from FSDK, e.g. a tool consumed by a future VM/appliance image. Use when the deliverable is `elements/<name>/<name>.bst` + `<name>-stack.bst` only, not a full distroless image."
metadata:
  type: procedure
  context7-sources:
    - /apache/buildstream
---

# Add an FSDK Component (no OCI image)

Use when a task asks for a buildable, checkout-able BuildStream component and
its stack, but explicitly *not* an OCI image (`elements/oci/*.bst`) — e.g. a
piece that a later VM/appliance task will consume. For the full three-element
OCI image pattern, see [add-new-image.md](../add-new-image.md) instead.

Live examples: `elements/qemu-img/` (meson), `elements/lab-runner/*.bst`
(tar/binary manual elements).

## 1. Research with Context7 first

Resolve the upstream project's *current* build-system and packaging docs
before picking versions or dependency elements — build systems change between
major versions. Don't stop at the dependency manifest: verify which imports
are hard vs. optional (try/except, lazy) by reading upstream source, scoped to
the feature path your task needs.

## 2. Element kind: `manual` only

This project's `project.conf` does **not** register the `meson` or
`pyproject` element kinds (those live inside freedesktop-sdk's own project).
Every hand-authored element here uses `kind: manual` with hand-written shell —
see `elements/qemu-img/qemu-img.bst` (invokes `meson setup`/`ninja`/`meson
install` directly).

A bare `kind: manual` element with minimal `build-depends` has **no shell** in
its sandbox — `mkdir`, `cat`, etc. fail with "Staged artifacts do not provide
command 'sh'". Add a shell stack (e.g.
`freedesktop-sdk.bst:public-stacks/runtime-minimal.bst`; on FSDK 26.08 bash
moved, so check which stack provides it — `elements/brew/brew-prefix.bst`
stages `runtime-gnu` + `runtime-minimal` for this reason) to `build-depends`.

## 3. Dependency type is *when*, not just *whether*

The single easiest mistake; it fails silently with a confusing downstream
error (e.g. `ModuleNotFoundError` deep inside a build-time script):

- `build-depends` — staged **only** while building *this* element.
- `runtime-depends` — **not staged during this element's own build**, only
  visible to elements that depend on this one. A tool your own build commands
  invoke must NOT be listed here.
- `depends` (or `type: all`) — staged for this build **and** propagated to
  dependents' runtime. Use for anything needed both to build and to run.

Symptom: build passes configure and most of compile, then dies on a missing
module/tool while rendering/installing — the dep exists and built fine, it was
just never staged into *this* sandbox. Fix: move it to `depends`.

## 4. Don't force an expensive component for pkg-config metadata

If a build only needs `dependency('foo')` for a few path variables (not to
link), and nothing else here already build-depends on that FSDK component,
building it can be wildly disproportionate (e.g. `components/systemd.bst`
pulls lvm2/cryptsetup/tpm2-tss just to answer `systemdsystemunitdir`).

Pattern: a tiny build-depends-only shim element that writes minimal `.pc`
files with values taken verbatim from upstream's actual `.pc.in` templates,
evaluated at this repo's `prefix=/usr`; point `PKG_CONFIG_PATH` at it via the
consumer's `environment:`. Document it as build-time-only and revisit if the
real component becomes cheap. (First used by the since-removed
`cloud-init/systemd-unitdir-pkgconfig.bst` — see git history for the shape.)

## 5. Track, fetch, build, verify

```
just bst source track <name>/<name>.bst   # writes the real `ref:`
just bst source fetch <name>/<name>.bst
just bst build <name>/<name>.bst
just bst artifact checkout <name>/<name>.bst --directory <dir>
```

Never hand-write a `git_repo` `ref:` — it's a git-describe string
(`<tag>-<N>-g<sha>`), always generate via `source track`.

Confirm a build-only shim never leaks into the runtime closure:

```
just bst show --deps run <name>/<name>-stack.bst | grep <shim>   # expect no match
```

## 6. Manual-element failure modes that look like something else

All found in `elements/lab-runner/*`; none says what it means:

| Error | Real cause | Fix |
|---|---|---|
| `tar: X: Cannot change ownership to uid N, gid N: Invalid argument` | Release tarball records a build-machine uid/gid the sandbox cannot restore. | `tar -xzf archive.tar.gz --no-same-owner member` |
| `gzip: X.gz has 1 other link -- file ignored` (exit 2) | `gunzip` rewrites in place; BuildStream may stage the source as a hardlink. | `gunzip -c X.gz > X` — never decompress a staged source in place |
| `cc: fatal error: no input files` + earlier `sh: sed: command not found` | configure shells out to `sed`/`grep`/`awk` unchecked; the link failure is the symptom. | Declare every tool in `build-depends` (`components/sed.bst`, `grep.bst`, `gawk.bst`, ...) |
| `FAILURE Staging dependencies` / `Destination is a symlink, not a directory: /usr/sbin` | FSDK is merged-usr: `/usr/sbin`, `/bin`, `/lib` are symlinks; a real directory there cannot stage. | Install into `/usr/bin` (autotools: `--sbin-path=/usr/bin/foo`) |

General rule: **a manual element's sandbox contains only what you declared**;
missing tools fail silently before the step that reports the error. On a
link/staging failure, read upward for a `command not found` first.

`just validate` resolves the graph and passes for all four — verify against
the real build:

```
just bst build <name>/<name>.bst && just bst build <name>/<name>-runtime.bst
```

## 7. Validate installed payloads by importing them (not grepping config)

A config-text check can pass while a hard-imported dependency is still
missing — the failure only shows on first real import. Catch it at build
time, inside the element's own sandbox where both the just-installed tree and
its staged dependencies are present:

```yaml
install-commands:
- |
  env DESTDIR="%{install-root}" meson install -C %{build-dir} --no-rebuild
- |
  site_packages="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
  PYTHONPATH="%{install-root}${site_packages}" python3 -c "import importlib; importlib.import_module('<module>')"
```

`PYTHONPATH` points at `%{install-root}`'s site-packages (where the package's
own files just landed); its dependencies are already on the default
`sys.path` because they were staged at the sandbox root via
`depends`/`build-depends`.

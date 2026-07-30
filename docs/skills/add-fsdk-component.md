---
name: add-fsdk-component
description: Add a component + stack element (no OCI image) composed from FSDK, e.g. a tool consumed by a future VM/appliance image. Use when the deliverable is `elements/<name>/<name>.bst` + `<name>-stack.bst` only, not a full distroless image.
metadata:
  context7-sources:
    - /apache/buildstream
    - /canonical/cloud-init
---

# Add an FSDK Component (no OCI image)

Use when a task asks for a buildable, checkout-able BuildStream component and
its stack, but explicitly *not* an OCI image (`elements/oci/*.bst`) — e.g. a
piece that a later VM/appliance task will consume. For the full three-element
OCI image pattern, see [add-new-image.md](add-new-image.md) instead.

Worked example in this repo: `elements/cloud-init/` (cloud-init 26.2, built
for a future Lima-accessible QCOW2 that needs the NoCloud datasource).

## 1. Research with Context7 first

Resolve the upstream project's *current* build system and packaging docs
before picking versions or dependency elements — build systems change
between major versions (cloud-init switched from setuptools/distutils to
Meson in 25.3; guessing from stale blog posts/READMEs would have produced a
broken element). Don't stop at `requirements.txt`: verify which imports are
actually hard/unconditional vs. optional (try/except or lazily imported) by
reading the upstream source directly, scoped to the datasource/distro path
your task actually needs. For cloud-init + NoCloud + a generic/Debian-like
distro: `jinja2`, `pyyaml`, `requests`, and `jsonpatch` (+ its own
`jsonpointer` dependency) are mandatory; `configobj`, `oauthlib`, and
`jsonschema` are not (distro-specific modules, lazy MAAS-only import, and a
try/except-guarded schema-validation extra, respectively).

## 2. Element kind: `manual` only

This project's `project.conf` does **not** register the `meson` or
`pyproject` BuildStream element kinds (those only exist inside
freedesktop-sdk's own internal project). Every hand-authored element here
must use `kind: manual` with hand-written shell commands — see
`elements/qemu-img/qemu-img.bst` and `elements/cloud-init/cloud-init.bst` for
the pattern (meson invoked directly: `meson setup` / `ninja` / `meson
install`, or `python3 -m build` / `python3 -m installer` for pure-Python
deps with only a legacy `setup.py`, no `pyproject.toml`).

A bare `kind: manual` element with no/minimal `build-depends` has **no
shell** in its sandbox — `mkdir`, `cat`, etc. fail with "Staged artifacts do
not provide command 'sh'". Add
`freedesktop-sdk.bst:public-stacks/runtime-minimal.bst` (bash + coreutils +
glibc) to `build-depends` if the element needs to run shell commands beyond
invoking a single prebuilt tool.

## 3. Dependency type is not just "does it need to be there" — it's *when*

This is the single easiest mistake to make and it fails silently with a
confusing downstream error (e.g. `ModuleNotFoundError` deep inside a
build-time script, not a clear "dependency missing" message):

- `build-depends` — staged **only** while building *this* element. Not
  passed on to anything that later depends on this element.
- `runtime-depends` — the opposite: **not staged during this element's own
  build**, only required by/visible to elements that depend on *this*
  element at their runtime. If your own `install-commands`/`build-commands`
  invoke a tool that imports something, listing that something under
  `runtime-depends` will NOT make it available — it must be `build-depends`
  or plain `depends`.
- `depends` (no `type:`, or `type: all`) — staged for building this element
  **and** required at runtime by anything that depends on it. Use this for
  anything needed both to build and to run (e.g. cloud-init needs
  `jinja2`/`pyyaml`/`requests`/`jsonpatch` both to render its systemd unit
  templates at *install* time via `tools/render-template`, and to actually
  run at cloud-init runtime — so all of them are `depends`, not
  `runtime-depends`).

Symptom of getting this wrong: `cloud-init.bst` initially listed jinja2 etc.
under `runtime-depends`; the Meson build got past configure and most of
ninja, then failed with `ModuleNotFoundError: No module named 'jinja2'`
while rendering `cloud-init-local.service` via `tools/render-template` — the
dependency existed and was correctly built, it just was never staged into
*this* element's own sandbox. Switching to plain `depends:` fixed it
immediately, no other changes required.

## 4. Avoid forcing an expensive, uncached component just for pkg-config metadata

If your build only needs a `dependency('foo')` pkg-config lookup for a
handful of path variables (not to actually link/use the library), and no
other element in this repo already build-depends on that FSDK component
(cold shared-cache path), building it can be wildly disproportionate. Case
in point: `freedesktop-sdk.bst:components/systemd.bst` pulls in a
large transitive closure (lvm2, cryptsetup, kbd, tpm2-tss, ...) and nothing
else here forces it, so it triggered a full from-scratch build just to
answer `systemdsystemunitdir`/`systemdsystemgeneratordir`/`udevdir`.

Workaround used by `elements/cloud-init/systemd-unitdir-pkgconfig.bst`: hand
-author a tiny build-depends-only shim element that writes minimal
`.pc` files with values taken verbatim from the upstream project's *actual*
`.pc.in` templates (not guessed) evaluated at this repo's `prefix=/usr`
convention, then point `PKG_CONFIG_PATH` at it via the consuming element's
`environment:` block. Document the shim clearly as build-time-only and
revisit if the real component ever becomes cheap to build here (e.g.
another element starts depending on it for real).

## 5. Track, fetch, build, verify

```
just bst source track cloud-init/cloud-init.bst   # writes the real `ref:` (git-describe form)
just bst source fetch cloud-init/cloud-init.bst
just bst build cloud-init/cloud-init.bst
just bst artifact checkout cloud-init/cloud-init.bst --directory <dir>
```

Never hand-write a `git_repo` `ref:` — it's a git-describe string
(`<tag>-<N>-g<sha>`), not a plain tag or commit SHA; always generate it via
`source track`.

To confirm a build-only shim never leaks into the runtime closure of the
stack:

```
just bst show --deps run cloud-init/cloud-init-stack.bst | grep <shim-element>   # expect no match
```

## Cloud-init specifics (for anyone extending this work)

- FSDK does **not** package `jsonpatch`, `jsonpointer`, `configobj`,
  `oauthlib`, or `jsonschema` as `python3-*` components. Only jsonpatch +
  jsonpointer were added here (the minimal mandatory set for NoCloud +
  generic distro); add the others only if a later task's distro/datasource
  scope actually requires them (re-verify against upstream source first).
- The NoCloud datasource (needed for Lima's `cidata.iso`) is recognized
  without any extra config: it's first in cloud-init's built-in
  `CFG_BUILTIN["datasource_list"]` fallback (`cloudinit/settings.py`), and
  this element's rendered `/etc/cloud/cloud.cfg` does not override
  `datasource_list`, so the default applies as-is.
- `bash_completion` is disabled (`-Dbash_completion=false`) since distroless
  images ship no shell/completions (AGENTS.md hard rule 4).

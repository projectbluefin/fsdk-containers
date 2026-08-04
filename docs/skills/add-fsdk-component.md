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
for a cloud-image lane that needs the NoCloud datasource).

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

## 6. Manual-element failure modes that look like something else

Every one of these was found in a single session, in `elements/lab-runner/*`,
and none of them says what it means. Recognise them by their error text:

| Error | Real cause | Fix |
|---|---|---|
| `tar: X: Cannot change ownership to uid N, gid N: Invalid argument`, then `tar: Exiting with failure status` | The release tarball records a build-machine uid/gid. The sandbox cannot restore it, so `tar` exits non-zero even though the member extracted correctly. | `tar -xzf archive.tar.gz --no-same-owner member` |
| `gzip: X.gz has 1 other link -- file ignored` (exit 2) | `gunzip` rewrites in place, and BuildStream may stage the source as a hardlink. | `gunzip -c X.gz > X` — never decompress a staged source in place |
| `cc: fatal error: no input files` together with `sh: sed: command not found` | A configure script that shells out to `sed`/`grep`/`awk` *without checking for them*, generating a Makefile with an empty object list. The link failure is the symptom; the missing tool is the cause. | Declare every tool the build runs in `build-depends` (`components/sed.bst`, `components/grep.bst`, `components/gawk.bst`, `bootstrap/coreutils.bst`) |
| `FAILURE Staging dependencies` / `Destination is a symlink, not a directory: /usr/sbin` | freedesktop-sdk is a merged-usr sysroot: `/usr/sbin`, `/bin`, `/lib` are symlinks. An element that installs a *real* directory there cannot be staged. | Install into `/usr/bin` (e.g. autotools `--sbin-path=/usr/bin/foo`) |

The general rule behind all four: **a manual element's sandbox contains only
what you declared**, and the tools it lacks usually fail silently before the
step that actually reports an error. When a build fails at link or staging
time, read upward in the log for a `command not found` first.

Verify a fix against the real thing, not the graph:

```
just bst build lab-runner/nginx.bst          # the element alone
just bst build lab-runner/lab-runner-runtime.bst   # its staging into the compose
BUILD_IMAGE_NAME=lab-runner just build && BUILD_IMAGE_NAME=lab-runner just verify
```

`just validate` resolves the graph and would have passed for all four.

## Cloud-init specifics (for anyone extending this work)

- FSDK does **not** package `jsonpatch`, `jsonpointer`, `configobj`,
  `oauthlib`, or `jsonschema` as `python3-*` components. `jsonpatch`,
  `jsonpointer`, and `configobj` were added here (see next point for why
  `configobj` is mandatory, not optional); add `oauthlib`/`jsonschema` only
  if a later task's distro/datasource scope actually requires them
  (re-verify against upstream source first, and re-read the next point
  before assuming a hard-imported dep is skippable just because the
  *feature* it backs looks inactive/irrelevant).
- **`configobj` is a mandatory runtime dependency, not an optional one —
  this was gotten wrong in an earlier pass of this work and corrected
  after review.** The original reasoning ("only RHEL/sysconfig distro
  modules and cc_landscape/cc_mcollective import it, none of which are on
  the NoCloud+generic-distro path") was checking the wrong thing: it
  matters whether upstream's Meson-rendered `cloud.cfg` *lists* a module by
  name in `cloud_config_modules`/`cloud_final_modules`, not whether that
  module's feature will ultimately activate. cloud-init's module loader
  (`cloudinit/config/modules.py:_fixup_modules`) imports **every** listed
  module unconditionally — the `_is_active()` activate-by-schema-key gate
  only runs *after* the import, in `run_section`. `cc_mcollective.py` is
  unconditionally listed in `cloud_final_modules` for **every** distro
  variant (`config/cloud.cfg.tmpl`), and `cc_landscape.py` is listed for
  the `debian`/`ubuntu`/`unknown` variants; both hard-import `from
  configobj import ConfigObj` at module scope. A missing `configobj`
  therefore breaks cloud-init's entire final stage on every boot, not just
  those two features — a `datasource_list` grep or any check that stops at
  "is NoCloud recognized" will never catch this class of bug. **Lesson:**
  when scoping a hard-imported dependency as skippable, check what's
  *listed* in the rendered default config's module lists, not just what
  functionality you expect to use.
- **The rendered `cloud.cfg`'s module lists are not fully deterministic.**
  `tools/render-template` defaults `--variant` to
  `cloudinit.util.system_info()["variant"]` (auto-detected from the
  *build sandbox's* `/etc/os-release`) when Meson's `cloud.cfg` custom_target
  doesn't pass `--variant` explicitly (and it doesn't, as of 26.2). This
  means which variant-gated modules (e.g. `landscape`, `snap`,
  `apt_configure`) appear in the installed `cloud.cfg` can vary depending on
  what the build sandbox's OS identifies as. `cc_mcollective` is the one
  constant across all variants; don't rely solely on grepping the installed
  `cloud.cfg` to decide whether a hard-imported dependency is needed —
  check upstream's `config/cloud.cfg.tmpl` source directly for whether a
  module is *ever* unconditionally or commonly listed, and test-import it
  regardless of what happens to render in your own build.
- The NoCloud datasource (needed for a `cidata.iso` seed) is recognized
  without any extra config: it's first in cloud-init's built-in
  `CFG_BUILTIN["datasource_list"]` fallback (`cloudinit/settings.py`), and
  this element's rendered `/etc/cloud/cloud.cfg` does not override
  `datasource_list`, so the default applies as-is.
- `bash_completion` is disabled (`-Dbash_completion=false`) since distroless
  images ship no shell/completions (AGENTS.md hard rule 4).
- The runtime closure also needs `freedesktop-sdk.bst:components/
  util-linux-full.bst` (provides `blkid`/`mount`, used by `ds-identify` and
  `cc_disk_setup`/`cc_mounts` to find and mount a labelled NoCloud
  `cidata`/`CIDATA` ISO9660 volume — this pulls in
  `components/util-linux.bst`, which is where `blkid` itself lives, as its
  own runtime-dep, so depending on `util-linux-full` alone is sufficient)
  and `freedesktop-sdk.bst:components/shadow.bst` (provides `useradd`/
  `usermod`, used by `cc_users_groups` to create/update a user injected
  dynamically via `--uid`). Both are `runtime-depends` on
  `cloud-init.bst` itself (needed only when cloud-init *runs*, not to build
  it), not stack-level additions — matching how cloud-init's own mandatory
  Python deps are attached directly to the component.

## Validating a hard-import dependency fix (not just config-text presence)

A `datasource_list`/`grep`-only check can pass while a hard-imported
dependency is still missing (see the `configobj` case above) — the failure
only shows up when the actual module is imported, which for cloud-init only
happens on a real boot. Catch this at build time instead, inside the
element's own sandbox where the just-installed package tree and all its
staged dependencies are both present:

```yaml
install-commands:
- |
  env DESTDIR="%{install-root}" meson install -C %{build-dir} --no-rebuild
- |
  site_packages="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
  PYTHONPATH="%{install-root}${site_packages}" python3 -c "
  import importlib
  importlib.import_module('cloudinit.config.cc_mcollective')
  importlib.import_module('cloudinit.config.cc_landscape')
  "
```

`PYTHONPATH` must point at `%{install-root}`'s site-packages (where the
package-under-build's own files just landed via `DESTDIR`), while its
*dependencies* (jinja2, configobj, etc.) are already on the default
`sys.path` because they were staged at the real sandbox root via
`depends`/`build-depends`. See `elements/cloud-init/cloud-init.bst`'s
install-commands for the full version, which derives the module name list
from the installed `cloud.cfg` itself plus an explicit allowlist for
modules known to be variant-gated (see the non-determinism point above).

## Validating discovery/provisioning tools without a live VM

When a task needs evidence that runtime tools (`blkid`, `mount`,
`useradd`, ...) actually work for their intended purpose, but a live VM
boot is out of scope, exercise the *extracted* artifact's binaries
directly on the host — FSDK's glibc-linked binaries generally run
standalone outside the BuildStream sandbox:

- **`blkid -p <file>`** probes a filesystem/ISO image without mounting
  (no root needed) — build a labelled test image with
  `xorrisofs -volid cidata -joliet -rock -output cidata.iso meta-data
  user-data` and confirm `blkid -p` reports `LABEL="cidata"
  TYPE="iso9660"`, exactly what NoCloud/`ds-identify` key off of.
- **`useradd -P <scratch-dir> --uid <n> <name>`** (`-P`/`--prefix`, not
  `-R`/`--root`/chroot) points `useradd` at an alternate `/etc/passwd` etc.
  without requiring root or a real chroot — seed a scratch dir with empty
  `passwd`/`shadow`/`group`/`gshadow`/`subuid`/`subgid` and a minimal
  `login.defs`, then confirm the resulting `passwd` entry has the exact
  UID requested, simulating dynamic per-VM user injection.
- An actual `mount -o loop` of a test ISO will fail without root/CAP_SYS_ADMIN
  in a non-VM environment — that's expected and is the real boundary of
  "without a live VM"; use `xorriso -indev <iso> -find /` and `-osirrox on
  -extract` to enumerate/read the ISO's contents read-only as
  content-equivalent evidence instead.

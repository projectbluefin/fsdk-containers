# Adding an FSDK Component — cloud-init specifics

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

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

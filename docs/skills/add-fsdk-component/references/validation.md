# Adding an FSDK Component — validation recipes

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

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

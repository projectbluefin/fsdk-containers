kind: manual
description: |
  Cloud-init, built from upstream source with its native Meson build system
  (upstream switched from setuptools to Meson in 25.3 — see
  doc/rtd/reference/breaking_changes.rst). Installs the cloud-init Python
  package, its systemd units/generator, and /etc/cloud/cloud.cfg so the
  NoCloud datasource is recognized out of the box.

  This project does not register BuildStream's `meson` element kind (only
  freedesktop-sdk's own project does), so the Meson invocation is spelled out
  by hand here rather than via `kind: meson`.

  bash-completion is disabled: distroless images ship no shell, so completion
  scripts are dead weight (see AGENTS.md hard rule 4).

sources:
- kind: git_repo
  url: github:canonical/cloud-init.git
  track: "2[0-9].*"
  exclude:
  - "*rc*"
  ref: 26.2-0-g0578e3b752afe67d8366300841e1252cb987f91f
build-depends:
- freedesktop-sdk.bst:public-stacks/buildsystem-meson.bst
- freedesktop-sdk.bst:components/findutils.bst
# Build-only: provides the `systemd`/`udev` pkg-config files Meson queries
# for systemdsystemunitdir/systemdsystemgeneratordir/udevdir, without
# forcing a full from-source build of components/systemd.bst just to
# answer three path lookups. See systemd-unitdir-pkgconfig.bst for why.
- cloud-init/systemd-unitdir-pkgconfig.bst

# Needed both in this element's own build sandbox (tools/render-template
# imports cloudinit.templater/util at Meson install time to render the
# systemd unit templates and cloud.cfg) and at actual cloud-init runtime,
# so these are plain (build+runtime) dependencies, not build-only.
depends:
- freedesktop-sdk.bst:components/python3.bst
- freedesktop-sdk.bst:components/python3-jinja2.bst
- freedesktop-sdk.bst:components/python3-pyyaml.bst
- freedesktop-sdk.bst:components/python3-requests.bst
# Not packaged by FSDK: cloud-init hard-imports `jsonpatch` at module load
# (cloudinit/handlers/cloud_config.py), so it is a mandatory runtime
# dependency, not an optional extra.
- cloud-init/python3-jsonpatch.bst
- cloud-init/python3-jsonpointer.bst
# Not packaged by FSDK: cloud-init's module loader
# (cloudinit/config/modules.py:_fixup_modules) imports *every* module
# named in cloud_config_modules/cloud_final_modules unconditionally,
# before the per-module activation check runs. cc_mcollective.py
# (unconditionally listed in cloud_final_modules for every distro variant)
# and cc_landscape.py (listed for the debian/ubuntu/unknown variants) both
# hard-import `from configobj import ConfigObj` at module scope, so a
# missing configobj breaks cloud-init's final stage on every boot, not
# just those two features. See the "Focused validation" install step
# below and docs/skills/add-fsdk-component.md for the full analysis.
- cloud-init/python3-configobj.bst

# Runtime-only (not needed to build cloud-init itself): cloud-init shells
# out to these at actual boot time, not during its own Meson build.
runtime-depends:
# ds-identify (tools/ds-identify, run by the systemd generator before
# cloud-init-local.service) and cc_disk_setup/cc_mounts use `blkid`/`mount`
# to find and mount the NoCloud datasource's labelled `cidata` ISO9660
# volume (Lima's cidata.iso). `components/util-linux.bst` (which provides
# blkid) is itself a runtime-dep of util-linux-full, so depending on
# util-linux-full alone pulls in both.
- freedesktop-sdk.bst:components/util-linux-full.bst
# cc_users_groups calls `useradd`/`usermod` (with `--uid`, `--gid`,
# `--groups`, etc., as supplied by Lima's per-VM dynamic user metadata in
# the NoCloud seed) to create/update the injected user; cc_ssh needs
# `usermod`/`chpasswd`-adjacent tooling from the same package.
- freedesktop-sdk.bst:components/shadow.bst

variables:
  strip-binaries: ''
  build-dir: _builddir
  meson-local: >-
    -Dbash_completion=false

config:
  configure-commands:
  - |
    meson setup %{build-dir} \
      --prefix=/usr \
      --sysconfdir=/etc \
      --libexecdir=lib \
      -Dinit_system=systemd \
      %{meson-local}

  build-commands:
  - |
    ninja -v -j ${JOBS:-1} -C %{build-dir}

  install-commands:
  - |
    env DESTDIR="%{install-root}" meson install -C %{build-dir} --no-rebuild
  - |
    # Focused import-viability check, not just datasource_list grep: the
    # module loader (cloudinit/config/modules.py:_fixup_modules) imports
    # *every* module named in cloud_init_modules/cloud_config_modules/
    # cloud_final_modules unconditionally, before the per-module
    # _is_active() activation check runs — a hard-import of a missing
    # dependency anywhere in that set breaks the whole stage on every boot,
    # not just that module's feature. This previously would have missed
    # the ConfigObj gap entirely. Import every module actually enabled in
    # the rendered cloud.cfg, plus cc_landscape/cc_mcollective explicitly:
    # cc_landscape's presence in cloud_final_modules depends on the Meson
    # `--variant` auto-detected from the *build sandbox's* /etc/os-release
    # (upstream's tools/render-template defaults to `util.system_info()`
    # when no --variant is passed), so it is not guaranteed to be listed
    # on every build — both it and cc_mcollective (always listed, in every
    # variant) are the two modules known to hard-import ConfigObj, so they
    # are always checked regardless of what the rendered cloud.cfg says.
    site_packages="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
    modules="$(python3 -c "
    import yaml
    cfg = yaml.safe_load(open('%{install-root}/etc/cloud/cloud.cfg'))
    names = set()
    for key in ('cloud_init_modules', 'cloud_config_modules', 'cloud_final_modules'):
        for m in cfg.get(key, []):
            names.add(m if isinstance(m, str) else next(iter(m)))
    names.update(('landscape', 'mcollective'))
    print(' '.join(sorted(names)))
    ")"
    PYTHONPATH="%{install-root}${site_packages}" python3 -c "
    import importlib, sys
    names = '$modules'.split()
    failed = []
    for name in names:
        mod = 'cloudinit.config.cc_' + name
        try:
            importlib.import_module(mod)
        except Exception as exc:
            failed.append((mod, repr(exc)))
    if failed:
        for mod, exc in failed:
            print('IMPORT FAILED:', mod, exc, file=sys.stderr)
        sys.exit(1)
    print('OK: imported', len(names), 'cloud-init config modules with no missing dependencies')
    "

  strip-commands:
  - |
    %{strip-binaries}

environment:
  JOBS: |
    %{max-jobs}
  # Points meson's `dependency('systemd')`/`dependency('udev')` pkg-config
  # lookups at the shim from systemd-unitdir-pkgconfig.bst.
  PKG_CONFIG_PATH: /opt/fsdk-shims/pkgconfig

environment-nocache:
- JOBS

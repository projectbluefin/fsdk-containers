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

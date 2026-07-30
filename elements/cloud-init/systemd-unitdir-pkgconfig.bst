kind: manual
description: |
  Build-only pkg-config shim providing `systemd.pc` and `udev.pc`, so
  cloud-init's Meson build (`dependency('systemd')` / `dependency('udev')`)
  can resolve `systemdsystemunitdir`, `systemdsystemgeneratordir`, and
  `udevdir` without pulling in a full `freedesktop-sdk.bst:components/systemd.bst`
  build — that component has a large, expensive-to-build transitive closure
  (lvm2, cryptsetup, kbd, tpm2-tss, ...) purely to answer three path queries,
  and depending on it triggered a full from-source systemd rebuild in this
  repo (nothing else here build-depends on components/systemd.bst yet, so
  the shared cache had no hit for it).

  The three variables below are not guessed: they are the literal defaults
  from upstream systemd's own pkg-config templates
  (src/core/systemd.pc.in, src/udev/udev.pc.in as of the systemd main
  branch) evaluated at prefix=/usr, which matches this project's
  `indep-libdir: "%{prefix}/lib"` convention
  (freedesktop-sdk include/install-dirs.yml) — i.e. exactly what
  components/systemd.bst would itself produce for these two files. These
  paths are architecture-independent (unit/generator/udev-rule directories
  hold data, not compiled objects), so no per-arch branching is needed.

  This element is build-depends-only: nothing in cloud-init-stack.bst or
  downstream depends on it, so it never reaches a runtime image. If a future
  task makes components/systemd.bst cheap to consume here (e.g. another
  element already forces it to be built), prefer switching cloud-init.bst
  back to depending on it directly and deleting this shim.

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ''
  shim-pkgconfig-dir: '%{install-root}/opt/fsdk-shims/pkgconfig'

config:
  install-commands:
  - |
    mkdir -p %{shim-pkgconfig-dir}
    cat > %{shim-pkgconfig-dir}/systemd.pc <<'EOF'
    prefix=/usr
    systemd_system_unit_dir=${prefix}/lib/systemd/system
    systemdsystemunitdir=${systemd_system_unit_dir}
    systemd_system_generator_dir=${prefix}/lib/systemd/system-generators
    systemdsystemgeneratordir=${systemd_system_generator_dir}

    Name: systemd
    Description: systemd System and Service Manager (build-time path shim)
    Version: 257
    EOF
    cat > %{shim-pkgconfig-dir}/udev.pc <<'EOF'
    prefix=/usr
    udev_dir=${prefix}/lib/udev
    udevdir=${udev_dir}

    Name: udev
    Description: udev (build-time path shim)
    Version: 257
    EOF

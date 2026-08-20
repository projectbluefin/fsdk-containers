kind: manual
description: Compile qemu-img from source.

sources:
  - kind: tar
    url: https://download.qemu.org/qemu-%{qemu_version}.tar.xz
    ref: da5fcffc32762820568b828ed430a728864d34d50b6d2f30358597760cbb0523

build-depends:
  # FSDK 26.08 removed the shell from runtime-minimal; these commands

  # are shell scripts, so declare the interpreter explicitly.

  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/pkg-config.bst
  - freedesktop-sdk.bst:components/python3.bst
  - freedesktop-sdk.bst:components/python3-distlib.bst
  - freedesktop-sdk.bst:components/python3-setuptools.bst
  - freedesktop-sdk.bst:components/python3-packaging.bst
  # qemu >= 9 builds a Python venv for its build tooling; wheel and pip must be
  # present or mkvenv tries to fetch them from PyPI, which the sandbox blocks.
  - freedesktop-sdk.bst:components/python3-wheel.bst
  - freedesktop-sdk.bst:components/python3-pip.bst
  - freedesktop-sdk.bst:components/ninja.bst
  - freedesktop-sdk.bst:components/meson.bst
  - freedesktop-sdk.bst:components/grep.bst
  - freedesktop-sdk.bst:components/sed.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/diffutils.bst
  - freedesktop-sdk.bst:components/make.bst
  - freedesktop-sdk.bst:components/which.bst

depends:
  - freedesktop-sdk.bst:components/glib.bst
  - freedesktop-sdk.bst:components/pixman.bst

variables:
  strip-binaries: ""
  # renovate: datasource=gitlab-tags depName=qemu-project/qemu extractVersion=^v(?<version>.+)$
  qemu_version: 11.0.3
  hardening-flags: ""
  (?):
    - arch == "x86_64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -fcf-protection=full"
    - arch == "aarch64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -mbranch-protection=standard"

config:
  configure-commands:
    - |
      # --disable-download: qemu >= 9 resolves its Python build deps (qemu.qmp,
      # meson) into a venv and reaches for PyPI when they are missing.
      # BuildStream sandboxes have no network, so use the wheels qemu bundles
      # in python/wheels/ instead of failing on DNS resolution.
      ./configure \
        --prefix=/usr \
        --extra-cflags="%{hardening-flags}" \
        --disable-system \
        --disable-user \
        --enable-tools \
        --disable-docs \
        --disable-download \
        --disable-guest-agent \
        --disable-werror \
        --disable-sdl \
        --disable-gtk \
        --disable-vnc \
        --disable-virtfs \
        --disable-vde \
        --disable-brlapi \
        --disable-cap-ng \
        --disable-curl \
        --disable-fdt \
        --disable-kvm \
        --disable-libiscsi \
        --disable-libnfs \
        --disable-mpath \
        --disable-numa \
        --disable-opengl \
        --disable-rbd \
        --disable-rdma \
        --disable-spice \
        --disable-usb-redir \
        --disable-vhost-net \
        --disable-vte \
        --disable-xen

  build-commands:
    - |
      ninja -C build qemu-img

  install-commands:
    - |
      install -D -m 755 build/qemu-img "%{install-root}/usr/bin/qemu-img"

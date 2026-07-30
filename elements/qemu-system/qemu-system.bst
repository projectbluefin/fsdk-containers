kind: manual
description: Compile the host QEMU system emulator for the donate-clanker microVM.

sources:
  - kind: tar
    url: https://download.qemu.org/qemu-8.2.2.tar.xz
    ref: 847346c1b82c1a54b2c38f6edbd85549edeb17430b7d4d3da12620e2962bc4f

build-depends:
  - freedesktop-sdk.bst:components/pkg-config.bst
  - freedesktop-sdk.bst:components/python3.bst
  - freedesktop-sdk.bst:components/python3-distlib.bst
  - freedesktop-sdk.bst:components/python3-setuptools.bst
  - freedesktop-sdk.bst:components/python3-packaging.bst
  - freedesktop-sdk.bst:components/ninja.bst
  - freedesktop-sdk.bst:components/meson.bst
  - freedesktop-sdk.bst:components/grep.bst
  - freedesktop-sdk.bst:components/sed.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/diffutils.bst
  - freedesktop-sdk.bst:components/make.bst
  - freedesktop-sdk.bst:components/which.bst
  - freedesktop-sdk.bst:bootstrap/linux-headers.bst

depends:
  - freedesktop-sdk.bst:components/glib.bst
  - freedesktop-sdk.bst:components/pixman.bst
  - freedesktop-sdk.bst:components/zlib.bst
  - freedesktop-sdk.bst:components/libcap-ng.bst
  - freedesktop-sdk.bst:components/libslirp.bst

variables:
  strip-binaries: ""
  hardening-flags: ""
  qemu-target: ""
  qemu-target-list: ""
  (?):
    - arch == "x86_64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -fcf-protection=full"
        qemu-target: "x86_64"
        qemu-target-list: "x86_64-softmmu"
    - arch == "aarch64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -mbranch-protection=standard"
        qemu-target: "aarch64"
        qemu-target-list: "aarch64-softmmu"

config:
  configure-commands:
    - |
      ./configure \
        --prefix=/usr \
        --target-list="%{qemu-target-list}" \
        --extra-cflags="%{hardening-flags}" \
        --enable-kvm \
        --disable-user \
        --disable-tools \
        --disable-docs \
        --disable-guest-agent \
        --disable-werror \
        --disable-sdl \
        --disable-gtk \
        --disable-vnc \
        --disable-virtfs \
        --disable-vde \
        --disable-brlapi \
        --disable-curl \
        --disable-fdt \
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
      ninja -C build qemu-system-%{qemu-target}

  install-commands:
    - |
      install -D -m 755 "build/qemu-system-%{qemu-target}" \
        "%{install-root}/usr/bin/qemu-system-%{qemu-target}"

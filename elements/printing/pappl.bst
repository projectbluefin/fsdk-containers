kind: manual
description: PAPPL, the printer application framework, built against the printing stack's CUPS.

# Shared by every printer application consuming printing/base.bst. The
# compiled-in state/socket dirs are only used when a PAPPL app runs as root
# (state in /var/lib/<app>.state, spool in /var/spool/<app>, socket in
# /run/<app>.sock, where <app> is the application's own base name). The
# printer application images run as nonroot, so these are neutral defaults,
# not per-application paths.
sources:
- kind: git_repo
  url: github:michaelrsweet/pappl.git
  # renovate: datasource=github-tags depName=michaelrsweet/pappl
  track: v1.4.12
  ref: v1.4.12-0-g6db8e137557ad84662e78d24fdb2a591c621f4ac
- kind: patch_queue
  path: patches/printing/pappl

build-depends:
- freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

depends:
- freedesktop-sdk.bst:components/avahi-libs.bst
- freedesktop-sdk.bst:components/cups.bst
- freedesktop-sdk.bst:components/gnutls.bst
- freedesktop-sdk.bst:components/jpeg.bst
- freedesktop-sdk.bst:components/libpng.bst
- freedesktop-sdk.bst:components/libusb.bst

config:
  configure-commands:
  - |
    ./configure \
      --prefix=/usr \
      --libdir="%{libdir}" \
      --disable-libpam \
      --disable-static \
      --enable-shared \
      --enable-libjpeg \
      --enable-libpng \
      --enable-libusb \
      --with-dnssd=avahi \
      --with-tls=gnutls \
      --with-papplstatedir=/var \
      --with-papplsockdir=/run
  build-commands:
  - make -j2
  install-commands:
  - make DESTDIR="%{install-root}" install

public:
  bst:
    split-rules:
      devel:
        (>):
        # The default devel rule only matches the .pc files, so the empty
        # directory would survive a runtime-only compose.
        - '%{libdir}/pkgconfig'

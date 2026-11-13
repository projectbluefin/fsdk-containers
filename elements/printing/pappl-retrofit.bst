kind: manual
description: pappl-retrofit, the CUPS driver retrofit layer for PAPPL printer applications.

# Pin a reviewed master commit for fixes newer than the 1.0b3 release.
# `just track printing/pappl-retrofit.bst` moves it to master's HEAD;
# review the upstream diff like any other bump.
sources:
- kind: git_repo
  url: github:OpenPrinting/pappl-retrofit.git
  track: master
  ref: 39b6313c607642f1844cb949c74ce929b3d592b7

build-depends:
- freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

depends:
- printing/pappl.bst
- freedesktop-sdk.bst:components/cups.bst
- freedesktop-sdk.bst:components/libcupsfilters.bst
- freedesktop-sdk.bst:components/libppd.bst

config:
  configure-commands:
  - ./autogen.sh
  - ./configure --prefix=/usr --libdir="%{libdir}"
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

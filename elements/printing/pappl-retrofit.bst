kind: manual
description: pappl-retrofit, the CUPS driver retrofit layer for PAPPL printer applications.

# Upstream has no release newer than 1.0b2, which predates the libcupsfilters
# 2.x API, so this is pinned to a reviewed commit on master. `bst source track`
# (`just track printing/pappl-retrofit.bst`) moves it to master's HEAD; review
# that diff like any other bump.
sources:
- kind: git_repo
  url: github:OpenPrinting/pappl-retrofit.git
  track: master
  ref: 1626b338fc8b92a99c2c1a483ac39c739d71b305

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

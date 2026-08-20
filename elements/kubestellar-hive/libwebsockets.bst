kind: manual
description: |
  DRAFT (Wave 0 spike) — libwebsockets, needed by ttyd. FSDK has NO
  libwebsockets component (checked the components/ tree at the pinned
  junction ref freedesktop-sdk-26.08beta.2), so build it here.

  Upstream hive sidesteps this entirely: v2/Dockerfile downloads ttyd's
  PREBUILT release binary (ttyd 1.7.7) instead of building from source.
  Building the chain (libwebsockets -> ttyd) keeps this repo's
  source-build + hardening-flag conventions; cmake, gcc, openssl, zlib and
  json-c all exist as FSDK components at the pinned ref (cmake/json-c
  resolve and are cached/verified; openssl verified cached).

  Wave 4 validation needed: exact -DLWS_* flag set (ttyd needs
  LWS_WITH_SSL, LWS_WITH_LIBUV is OFF — no libuv in FSDK), and whether a
  static LWS (LWS_WITH_SHARED=OFF + static link into ttyd) produces a
  smaller runtime slice than shipping the shared lib.

sources:
  - kind: git_repo
    url: github:warmcat/libwebsockets.git
    # renovate: datasource=git-refs depName=warmcat/libwebsockets
    track: v4.3.9
    ref: fdd30f26fd9c093ae83787b9a529ec5dd53e91ab

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/cmake.bst
  - freedesktop-sdk.bst:components/ninja.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/make.bst
  - freedesktop-sdk.bst:components/pkg-config.bst
  - freedesktop-sdk.bst:components/binutils.bst

depends:
  - freedesktop-sdk.bst:components/openssl.bst
  - freedesktop-sdk.bst:components/zlib.bst

variables:
  strip-binaries: ""
  hardening-flags: ""
  (?):
    - arch == "x86_64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -fcf-protection=full"
    - arch == "aarch64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -mbranch-protection=standard"

config:
  configure-commands:
    - |
      cmake -S . -B build -G Ninja \
        -DCMAKE_INSTALL_PREFIX="%{prefix}" \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DCMAKE_C_FLAGS="%{hardening-flags}" \
        -DLWS_WITH_SSL=ON \
        -DLWS_WITH_LIBUV=OFF \
        -DLWS_WITHOUT_TESTAPPS=ON \
        -DLWS_WITHOUT_TEST_SERVER=ON \
        -DLWS_WITHOUT_TEST_PING=ON \
        -DLWS_WITHOUT_TEST_CLIENT=ON \
        -DLWS_WITH_SHARED=ON

  build-commands:
    - |
      ninja -C build

  install-commands:
    - |
      ninja -C build install

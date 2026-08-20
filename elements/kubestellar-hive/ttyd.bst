kind: manual
description: |
  DRAFT (Wave 0 spike) — ttyd 1.7.7 (the exact version upstream's
  v2/Dockerfile pins for its prebuilt binary download; TTYD_VERSION=1.7.7).

  ttyd is a C program linking libwebsockets + json-c + openssl. FSDK ships
  json-c and openssl but NOT libwebsockets, so this builds on the local
  libwebsockets.bst element. ttyd's CMake finds libwebsockets via
  pkg-config/cmake package config installed by libwebsockets.bst.

  NOTE (distroless tension): ttyd's purpose is serving a terminal over the
  web — upstream runs `ttyd ... /usr/local/bin/ttyd-tmux.sh`, which needs
  tmux AND a shell. A ttyd binary in a shell-less distroless image is only
  useful paired with the machine-image lane; see the stack description.

sources:
  - kind: git_repo
    url: github:tsl0922/ttyd.git
    # renovate: datasource=git-refs depName=tsl0922/ttyd
    track: "1.7.7"
    ref: 40e79c706be14029b391f369bee6613c31667abb

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/cmake.bst
  - freedesktop-sdk.bst:components/ninja.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/make.bst
  - freedesktop-sdk.bst:components/pkg-config.bst
  - freedesktop-sdk.bst:components/binutils.bst

depends:
  - kubestellar-hive/libwebsockets.bst
  - freedesktop-sdk.bst:components/json-c.bst
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
        -DCMAKE_C_FLAGS="%{hardening-flags}"

  build-commands:
    - |
      ninja -C build ttyd

  install-commands:
    - |
      install -D -m 755 build/ttyd "%{install-root}%{bindir}/ttyd"

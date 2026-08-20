kind: manual
description: |
  Build Node.js (LTS) from the upstream source tarball against FSDK's
  shared libraries. This is a C++/V8 tarball build, NOT a go_module build
  (corrects the batching table in projectbluefin/fsdk-containers#113).

sources:
  # Manual bump: nodejs.org publishes an authoritative SHASUMS256.txt per
  # release. Update node_version and ref together; verify with
  # `curl -sL https://nodejs.org/dist/vX.Y.Z/node-vX.Y.Z.tar.gz | sha256sum`
  # against https://nodejs.org/dist/vX.Y.Z/SHASUMS256.txt.
  - kind: tar
    url: https://nodejs.org/dist/v%{node_version}/node-v%{node_version}.tar.gz
    ref: 16fe258006a6e86844fbe05b3b5e1e5623ca8d3da54e32d98d9e83234bf25b01

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/make.bst
  - freedesktop-sdk.bst:components/ninja.bst
  # configure is a Python script and the gyp build runs under python3.
  - freedesktop-sdk.bst:components/python3.bst
  # configure locates every --shared-* dependency via pkg-config.
  - freedesktop-sdk.bst:components/pkg-config.bst
  # Shared libraries node links against (see depends: for the runtime side).
  - freedesktop-sdk.bst:components/openssl.bst
  - freedesktop-sdk.bst:components/zlib.bst
  - freedesktop-sdk.bst:components/c-ares.bst
  - freedesktop-sdk.bst:components/libnghttp2.bst
  - freedesktop-sdk.bst:components/brotli.bst
  - freedesktop-sdk.bst:components/icu.bst
  # configure, gyp and the generated build shell out to sed/grep/awk and
  # coreutils without checking for them; FSDK's sandbox has no ambient
  # userland (see lab-runner/nginx.bst for the failure mode).
  - freedesktop-sdk.bst:components/sed.bst
  - freedesktop-sdk.bst:components/grep.bst
  - freedesktop-sdk.bst:components/gawk.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  # strip(1) for the installed binary — an unstripped node is ~2.7 GB of V8
  # symbols, which both blows the distroless size budget and exceeds the
  # BuildBarn max blob size (~2.42 GiB), failing output capture.
  - freedesktop-sdk.bst:components/binutils.bst

depends:
  # node is linked against these shared libraries; declaring them here keeps
  # the runtime linkage explicit instead of relying on transitive luck.
  # All are FSDK components, so CVE patches land via the junction.
  - freedesktop-sdk.bst:components/openssl.bst
  - freedesktop-sdk.bst:components/zlib.bst
  - freedesktop-sdk.bst:components/c-ares.bst
  - freedesktop-sdk.bst:components/libnghttp2.bst
  - freedesktop-sdk.bst:components/brotli.bst
  - freedesktop-sdk.bst:components/icu.bst

variables:
  strip-binaries: ""
  node_version: 24.19.0
  hardening-flags: ""
  (?):
    - arch == "x86_64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -fcf-protection=full"
    - arch == "aarch64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -mbranch-protection=standard"

config:
  configure-commands:
    # gyp's ninja generator bakes CPPFLAGS/CFLAGS/CXXFLAGS from the
    # environment into build.ninja at configure time (the make generator
    # reads them at build time), so exporting before configure covers both.
    - export CFLAGS="%{hardening-flags}" CXXFLAGS="%{hardening-flags}"
    - |
      # --shared-*: link FSDK's CVE-patched openssl/zlib/c-ares/nghttp2/brotli
      #   instead of node's vendored copies. libuv/llhttp/ada/simdjson stay
      #   bundled — FSDK ships no components for them.
      # --with-intl=system-icu: the configure default (full-icu) downloads
      #   ICU at build time, which the network-less sandbox blocks. FSDK's
      #   icu 78.3 (verified at junction ref 45dfca2b / 26.08beta.2) satisfies
      #   node's minimum_icu=73 (tools/icu/icu_versions.json) and keeps full
      #   Intl parity with official node images. Size lever: switching to
      #   small-icu drops the icu runtime dep (~30 MB) at the cost of
      #   English-only Intl — a Wave 4 decision.
      # GRID NOTE 2026-08-09: ghost BuildBarn worker caches were poisoned
      # (empty-blob digest staged as brew's subuid content via
      # write-through-hardlink); fixed by truncating/deleting the corrupt
      # entries in /var/lib/buildbarn/worker/cache on both nodes.
      # --without-npm/--without-corepack: this is a distroless runtime image,
      #   not a dev environment (same shape as gcr.io/distroless/nodejs).
      # --ninja: gyp emits build.ninja; `make` stays the driver and forwards
      #   -j%{max-jobs} to ninja via MAKEFLAGS.
      ./configure \
        --prefix=/usr \
        --shared-openssl \
        --shared-zlib \
        --shared-cares \
        --shared-nghttp2 \
        --shared-brotli \
        --with-intl=system-icu \
        --without-npm \
        --without-corepack \
        --ninja

  build-commands:
    - make -j%{max-jobs}

  install-commands:
    - make install DESTDIR="%{install-root}"
    # Strip the installed binary: unstripped node is ~2.7 GB of V8 symbols.
    # bst's REAPI sandbox marks %{build-root} AND %{install-root} read-write,
    # so BOTH are declared Command outputs and captured into CAS — and
    # bb-storage rejects any single blob over ~2.42 GiB, which failed output
    # capture twice even though the compile itself succeeded. strip-binaries
    # stays "" (FSDK's strip stage would need debug-utils staged); strip the
    # one binary that matters explicitly instead.
    - strip --strip-unneeded "%{install-root}/usr/bin/node"
    # Layout on record (lands in the bst log; also the size feed for #127).
    - du -sh "%{install-root}"/* 2>/dev/null | sort -rh | head -30 || true
    # Capture only the installed /usr hierarchy — the compose element selects
    # from /usr anyway. Guard: [ -e ] for the empty-glob case under set -e.
    - |
      cd "%{install-root}"
      for p in *; do
        [ -e "$p" ] || continue
        [ "$p" = "usr" ] || rm -rf "$p"
      done
    # Drop the build tree (multi-GB out/ objects) so the declared build-root
    # output captures nothing. Must be the LAST command — it deletes the cwd.
    # bst's capture recreates the working directory when missing.
    - rm -rf "%{build-root}"

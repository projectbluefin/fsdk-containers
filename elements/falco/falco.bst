kind: manual
description: |
  Build falco (C++ CMake: engine + libsinsp/libscap + CO-RE eBPF probe) from
  source for a modern-eBPF-only distroless image.

  ══════════════════════════ WAVE 0 DRAFT — NOT EXPECTED TO BUILD ══════════════════════════
  Resolves (`bst show --deps none`) and declares all sources with verified
  hashes, but the build is BLOCKED on ~10 new dependency elements listed
  below. Do not `bst build` this in Wave 0. Full evidence: issue #113 Wave 0
  report for falco.

  ── Mechanism (corrects #113's `go_module` bucketing) ─────────────────────
  Falco 0.44.1 is a CMake/C++ project. Its CMake downloads everything at
  configure/build time, which fails on the network-less RE grid, so every
  download is either (a) declared as a BST source below, (b) redirected to a
  system/FSDK dependency via -DUSE_BUNDLED_*=OFF, or (c) disabled:

    BST sources declared here (hashes verified 2026-08-09):
      falco 0.44.1, falcosecurity/libs 0.25.4 (pin: cmake/modules/
      falcosecurity-libs.cmake), driver 10.2.0+driver (pin: driver.cmake —
      same repo, driver tag; only its HEADERS + modern_bpf/ probe sources are
      used, BUILD_DRIVER=OFF), falco-rules 5.1.0 (data; pin: rules.cmake).

    -D flag redirects to system deps (FSDK components exist):
      zlib, libbpf (FSDK v1.7.0 vs pin v1.3.0), libelf (via
      USE_DYNAMIC_LIBELF=ON), curl (FSDK 8.21.0 vs pin 8.7.1), openssl
      (FSDK 3.5.7 vs pin 3.1.4).
      NOTE: falcosecurity-libs.cmake force-sets USE_BUNDLED_{TBB,JSONCPP,
      VALIJSON,RE2,UTHASH}=ON as cache vars *without* FORCE, so explicit
      -D...=OFF on the cmake command line still wins. All five are passed.

    Disabled:
      ADD_FALCOCTL_DEPENDENCY=OFF  — upstream downloads a PREBUILT falcoctl
        0.13.0 Go binary (falcoctl.cmake). Building falcoctl from source
        needs the `go_module` plugin = Wave 1 (#115). The official
        falcosecurity/falco image itself rm's falcoctl, so shipping without
        it matches upstream's own flagship image.
      BUILD_DRIVER=OFF, ENABLE_DKMS=OFF — the kmod can only be built against
        the *target host's* kernel headers (or downloaded prebuilt at runtime
        by the falco-driver-loader bash script + a full clang/dkms toolchain
        image). Both are structurally incompatible with a reproducible
        distroless build. Modern eBPF (CO-RE) only: the probe is compiled at
        build time by clang (FSDK llvm component ships clang with the BPF
        target) + bpftool gen skeleton and embedded into libscap; at runtime
        it needs only kernel BTF from /sys on a >=5.8 kernel. No kernel
        headers, no shell, no downloads at runtime.
      CREATE_TEST_TARGETS/BUILD_FALCO_UNIT_TESTS=OFF — skips gtest download.

  ── Missing elements the build needs (the Wave 4 cost) ────────────────────
  FSDK has NO component for these (checked against all 708 components at
  freedesktop-sdk-26.08beta.2). Each needs a small BST element under
  elements/falco/deps/ with the exact upstream pin:
    compiled:  jsoncpp 1.9.5 · oneTBB v2022.1.0 · re2 2022-06-01 (pre-abseil,
               standalone) · yaml-cpp c2bec4c755 (post-0.8.0 commit) ·
               bpftool (github.com/libbpf/bpftool; small C make build needing
               libelf+zlib — required by `bpftool gen skeleton`)
    hdr-only:  valijson v1.0.2 (find_package CONFIG) · uthash v1.9.8 ·
               cxxopts v3.0.0 (CONFIG) · nlohmann-json v3.11.3 (CONFIG) ·
               cpp-httplib v0.23.1 (CONFIG)
  Add them to build-depends below as they land, then this element builds.

  ── The one remaining prebuilt binary: container plugin ───────────────────
  falco's top-level CMakeLists unconditionally include()s
  container_plugin.cmake, which downloads a PREBUILT Go plugin
  (container-0.7.1-linux-<arch>.tar.gz from download.falco.org) — there is NO
  cmake toggle. Options, in preference order:
    1. Wave 1+: build falcosecurity/plugins//plugins/container from source
       with go_module, then patch the ExternalProject URL to the staged .so
       (provenance stays clean).
    2. Patch the ExternalProject URL to file:// a BST-declared tarball
       (checksummed but prebuilt → provenance hole; must be labelled).
    3. Ship without it and strip `load_plugins: [container]` from falco.yaml
       — loses container/k8s metadata enrichment, falco's headline k8s value.
       Only viable as a smoke-test step, not a product.
  The patch itself is NOT written here: patch_queue sources live in the
  shared patches/ tree, off-limits to Wave 0.

  ── Runtime shape (see falco-stack.bst) ───────────────────────────────────
  Entrypoint is `/usr/bin/falco` directly (matches upstream's own CMD).
  Coherent distroless: no shell needed *unless* we keep the driver-loader
  script — we don't. Needs --privileged + /host mounts; root user is
  required (eBPF syscall capture), an intentional exception to #120.
  ═══════════════════════════════════════════════════════════════════════════

sources:
  # renovate: datasource=github-tags depName=falcosecurity/falco
  - kind: tar
    url: https://github.com/falcosecurity/falco/archive/refs/tags/0.44.1.tar.gz
    ref: 661d0dc62f0eb82352f8b176e423bd34fdc44ca4c98b3f329fd73d984f0c50f5
    directory: falco
  # falcosecurity/libs — pinned by falco's falcosecurity-libs.cmake
  - kind: tar
    url: https://github.com/falcosecurity/libs/archive/refs/tags/0.25.4.tar.gz
    ref: 272a5a0c05e7c10a658ed9649023e6179061a4ab29e012602893586ac64b5938
    directory: libs
  # driver (same repo, driver tag) — pinned by falco's driver.cmake
  - kind: tar
    url: https://github.com/falcosecurity/libs/archive/refs/tags/10.2.0+driver.tar.gz
    ref: 0e585f5fc2b76696ef2cb902f0901ea39a2f2df87e1f091f3348f968b9085f39
    directory: driver
  # falco_rules.yaml — pinned by falco's rules.cmake. The tarball ships the
  # bare yaml with no top-level directory, hence base-dir: '' (FSDK
  # precedent: docbook-xml.bst).
  - kind: tar
    url: https://download.falco.org/rules/falco-rules-5.1.0.tar.gz
    ref: 306bee1a828345bf40caa5ad637e6d6151c39173e80120b16bd4f9f8c166f91c
    directory: rules
    base-dir: ''

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/cmake.bst
  - freedesktop-sdk.bst:components/ninja.bst
  - freedesktop-sdk.bst:components/pkg-config.bst
  # clang (BPF target enabled) compiles the CO-RE probe
  - freedesktop-sdk.bst:components/llvm.bst
  # system deps redirected from bundled
  - freedesktop-sdk.bst:components/openssl.bst
  - freedesktop-sdk.bst:components/curl.bst
  - freedesktop-sdk.bst:components/zlib.bst
  - freedesktop-sdk.bst:components/libbpf.bst
  - freedesktop-sdk.bst:components/elfutils.bst
  # configure/build scripts shell out (per valkey/nginx precedent)
  - freedesktop-sdk.bst:components/sed.bst
  - freedesktop-sdk.bst:components/grep.bst
  - freedesktop-sdk.bst:components/gawk.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  # TODO(Wave 4): unblock the build by adding, under elements/falco/deps/:
  #   jsoncpp.bst (1.9.5) · tbb.bst (v2022.1.0) · re2.bst (2022-06-01) ·
  #   yaml-cpp.bst (c2bec4c755) · bpftool.bst ·
  #   valijson.bst / uthash.bst / cxxopts.bst / nlohmann-json.bst /
  #   cpp-httplib.bst (header-only)

variables:
  strip-binaries: ""
  hardening-flags: ""
  (?):
    - arch == "x86_64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -fcf-protection=full"
    - arch == "aarch64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -mbranch-protection=standard"

config:
  build-commands:
    # DRAFT — the intended configure line for the offline RE grid once the
    # dep elements above exist. Every upstream download is neutralised:
    #   FALCOSECURITY_LIBS_SOURCE_DIR / DRIVER_SOURCE_DIR skip the nested
    #   `execute_process(cmake)` tarball downloads (supported locals hooks);
    #   FALCOSECURITY_RULES_FALCO_PATH skips the rules download;
    #   ADD_FALCOCTL_DEPENDENCY=OFF skips the prebuilt falcoctl download;
    #   USE_BUNDLED_*=OFF redirects libraries to system deps;
    #   the container-plugin prebuilt download still needs the patch
    #   described in the header before this can go green.
    - |
      cmake -S falco -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_CXX_FLAGS="%{hardening-flags}" \
        -DCMAKE_C_FLAGS="%{hardening-flags}" \
        -DUSE_BUNDLED_DEPS=OFF \
        -DUSE_BUNDLED_TBB=OFF \
        -DUSE_BUNDLED_JSONCPP=OFF \
        -DUSE_BUNDLED_RE2=OFF \
        -DUSE_BUNDLED_VALIJSON=OFF \
        -DUSE_BUNDLED_UTHASH=OFF \
        -DUSE_BUNDLED_ZLIB=OFF \
        -DUSE_BUNDLED_LIBBPF=OFF \
        -DUSE_DYNAMIC_LIBELF=ON \
        -DUSE_BUNDLED_CXXOPTS=OFF \
        -DUSE_BUNDLED_NLOHMANN_JSON=OFF \
        -DUSE_BUNDLED_YAMLCPP=OFF \
        -DUSE_BUNDLED_CPPHTTPLIB=OFF \
        -DUSE_BUNDLED_CURL=OFF \
        -DUSE_BUNDLED_OPENSSL=OFF \
        -DFALCOSECURITY_LIBS_SOURCE_DIR="%{build-root}/libs" \
        -DDRIVER_SOURCE_DIR="%{build-root}/driver" \
        -DFALCOSECURITY_RULES_FALCO_PATH="%{build-root}/rules/falco_rules.yaml" \
        -DADD_FALCOCTL_DEPENDENCY=OFF \
        -DBUILD_DRIVER=OFF \
        -DENABLE_DKMS=OFF \
        -DBUILD_FALCO_MODERN_BPF=ON \
        -DBUILD_FALCO_UNIT_TESTS=OFF \
        -DCREATE_TEST_TARGETS=OFF
    - cmake --build build -- -j%{max-jobs}

  install-commands:
    - cmake --install build
    # The kmod/bpf driver sources and the driver-loader script must NOT ship:
    # modern-eBPF-only image, driver compiled in, no runtime toolchain.
    - rm -rf "%{install-root}/usr/src" "%{install-root}/usr/bin/falco-driver-loader"

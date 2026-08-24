kind: manual
description: |
  Falco (CNCF runtime security) — Wave 0 feasibility spike for issue #146.
  INERT: component + stack only, no OCI element, no targets.json entry.

  ════════════════════ THE FOUR WAVE-0 ANSWERS (verified 2026-08-20) ════════════════════

  1. MECHANISM — upstream binary tarball (`kind: remote`, download.falco.org).
     Three corrections to #113's assumptions (which bucketed falco as
     `go_module` / from-source):
       a) NOT go_module. Only falcoctl and the container plugin are Go, and
          both ship PREBUILT — falcoctl is even deleted from upstream's own
          distroless image, so nothing Go is ever compiled here.
       b) NOT an FSDK component: FSDK 26.08beta ships neither falco nor
          falcosecurity/libs (checked all 708 components).
       c) From-source CMake is out of spike scope and likely NEVER justified
          here. The previous draft (git history, PR #147 commit a6ceeae)
          documented it fully: falco's CMake downloads ~15 deps at configure
          time; neutralising that on the network-less RE grid needs ~10 new
          dep elements (jsoncpp, oneTBB, re2, yaml-cpp, bpftool, valijson,
          uthash, cxxopts, nlohmann-json, cpp-httplib) plus a patch_queue
          patch for the container-plugin prebuilt download — Wave 4 scale.
       d) HARD RULE 3 CHECK — does NOT apply. Upstream's own README calls
          `falcosecurity/falco` "Distroless", but by this repo's definition
          (AGENTS.md rule 4: distroless means no shell) it is not: the
          Dockerfile (docker/falco/Dockerfile at tag 0.44.1) is FROM
          cgr.dev/chainguard/wolfi-base and runs `apk add curl
          ca-certificates jq libstdc++`, shipping busybox /bin/sh + apk.
          There is no official shell-free image to consume, so building a
          genuinely distroless falco here is the value add, not a rebuild.
          Useful inheritance anyway: that image is built FROM THIS VERY
          TARBALL (downloads falco-${VERSION}-${ARCH}.tar.gz from
          download.falco.org, extracts it, rm's /usr/src driver sources and
          /usr/bin/falcoctl + /etc/falcoctl). This element does the same
          carve on top of our base stack instead of wolfi.

  2. DEPENDENCY SET — glibc only. readelf -d on usr/bin/falco (0.44.1):
     NEEDED = libm/libpthread/libc/libdl/librt + ld-linux — every heavy dep
     (openssl, curl, zlib, libbpf, libelf, jsoncpp, oneTBB, re2, yaml-cpp,
     gRPC/protobuf) is STATICALLY linked upstream. The shipped container
     plugin (usr/share/falco/plugins/libcontainer.so, needed by the default
     config: etc/falco/config.d/falco.container_plugin.yaml sets
     `load_plugins: [container]`) is also glibc-only. Build-time: tar, gzip,
     grep (smoke test), coreutils, runtime-gnu (shell). Runtime: base-stack
     provides glibc + gcc-libs + ca-certificates + tzdata — nothing further
     required.
     CAVEAT (cost of the prebuilt mechanism): the statically bundled deps
     (openssl, curl, gRPC, ...) do NOT inherit FSDK's CVE patching — the
     repo's core value proposition. A mid-cycle openssl CVE in falco cannot
     be fixed here; the only remedy is an upstream falco release, so this
     image tracks falco's release cadence for security fixes.

  3. RESOLVES + BUILDS: yes — `just bst build falco/falco-stack.bst`
     succeeds on the BuildBarn RE grid (see falco-stack.bst header for the
     run record). Includes an in-sandbox smoke test: `falco --version`
     executes during the build (only glibc must be staged) and printed
     "Falco version: 0.44.1 / Libs version: 0.25.4 / Driver: 10.2.0+driver".

  4. UPSTREAM VERSION + REF — falco 0.44.1 (latest release, published
     2026-06-11, github.com/falcosecurity/falco/releases/tag/0.44.1).
     Upstream publishes no .sha256 sidecar for the bin tarballs, so refs
     below were computed live 2026-08-20 (nginx-element precedent):
       x86_64:  https://download.falco.org/packages/bin/x86_64/falco-0.44.1-x86_64.tar.gz
       aarch64: https://download.falco.org/packages/bin/aarch64/falco-0.44.1-aarch64.tar.gz
     The embedded modern-eBPF (CO-RE) probe comes precompiled inside the
     binary — no clang/bpftool/kernel-headers needed at build or runtime
     (kernel >= 5.8 with BTF). The kmod path (usr/src driver sources +
     falco-driver-loader shell script + dkms) is deliberately NOT shipped,
     matching upstream's distroless image.

build-depends:
  # FSDK 26.08 removed the shell from runtime-minimal; these commands are
  # shell scripts, so declare the interpreter explicitly (kubectl.bst
  # precedent).
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/tar.bst
  - freedesktop-sdk.bst:components/gzip.bst
  # the smoke test below greps falco --version output
  - freedesktop-sdk.bst:components/grep.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  strip-binaries: ""
  # renovate: datasource=github-releases depName=falcosecurity/falco
  falco_version: 0.44.1

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "https://download.falco.org/packages/bin/x86_64/falco-%{falco_version}-x86_64.tar.gz"
          ref: bc5b7a3bdf26fc91e520fc20b3461613c6e725148437121697a8d20243132127
      - arch == "aarch64":
          url: "https://download.falco.org/packages/bin/aarch64/falco-%{falco_version}-aarch64.tar.gz"
          ref: 17ff67764cb84374ca0fcc98a733316f973a90f3457495df35a24bd839b4ce87
    filename: falco.tar.gz

config:
  install-commands:
    # --no-same-owner: the release tarball records the build-machine uid/gid,
    # which the sandbox cannot restore (docs/skills/add-fsdk-component
    # SKILL.md failure-modes table).
    - tar --no-same-owner -xzf falco.tar.gz
    # Ship exactly what upstream's own distroless image ships
    # (docker/falco/Dockerfile @0.44.1): falco + /etc/falco + the container
    # plugin. NOT shipped, same as upstream: /usr/src driver sources,
    # falcoctl, /etc/falcoctl.
    - |
      for src in falco-*/; do
        mkdir -p "%{install-root}/usr/bin" "%{install-root}/usr/share" "%{install-root}/etc"
        cp -a "${src}usr/bin/falco" "%{install-root}/usr/bin/falco"
        chmod 755 "%{install-root}/usr/bin/falco"
        cp -a "${src}usr/share/falco" "%{install-root}/usr/share/falco"
        cp -a "${src}etc/falco" "%{install-root}/etc/falco"
      done
    # Smoke-test in the sandbox: the binary's only NEEDED libraries are
    # glibc, staged here via runtime-gnu, so this must run and report the
    # pinned version. Catches a corrupt/incompatible artifact at build time
    # instead of at container start.
    - |
      "%{install-root}/usr/bin/falco" --version | grep -q "Falco version: %{falco_version}"

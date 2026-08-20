kind: stack
description: |
  Falco runtime dependencies (built on base stack) — DRAFT, Wave 0 spike.

  MECHANISM CORRECTION (vs issue #113's table): falco is NOT a `go_module`
  target. Falco is a C++ CMake project (falcosecurity/falco +
  falcosecurity/libs: libscap/libsinsp + eBPF drivers). The only Go parts —
  `falcoctl` and the `container` plugin — are downloaded by upstream's CMake
  as PREBUILT binaries (cmake/modules/falcoctl.cmake and
  container_plugin.cmake), not built from source. The `go_module` plugin is
  only relevant if we choose to build those two from source ourselves (a Wave
  1 dependency, not a blocker for the core engine).

  This stack assumes the build element (falco/falco.bst) links:
    - libsinsp/libscap STATICALLY (libs default BUILD_SHARED_LIBS=OFF)
    - jsoncpp / oneTBB / re2 / yaml-cpp STATICALLY (new elements to be added;
      see falco.bst header for the full inventory and pins)
    - openssl / curl / zlib / libbpf / libelf DYNAMICALLY from FSDK
      components (all exist; FSDK libbpf is v1.7.0, falco pins v1.3.0 but
      supports USE_BUNDLED_LIBBPF=OFF against a system libbpf)

  The image is modern-eBPF-only (CO-RE probe compiled at build time, embedded
  into libscap via `bpftool gen skeleton`; no kmod, no DKMS, no
  falco-driver-loader shell script, no runtime downloads). Runtime contract:
  --privileged + /host mounts (/proc, /etc, /var/run/docker.sock or CRI
  socket), per upstream's LABEL usage. Falco is an inherently privileged
  sensor: the #120 non-root contract does NOT apply (runs as root).

depends:
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/openssl.bst
  - freedesktop-sdk.bst:components/curl.bst
  - freedesktop-sdk.bst:components/zlib.bst
  - freedesktop-sdk.bst:components/libbpf.bst
  - freedesktop-sdk.bst:components/elfutils.bst
  # falco/falco.bst once it exists — commented out so this stack resolves
  # standalone in Wave 0. The build element is a draft blocked on ~10 new
  # dependency elements (see its header).
  # - falco/falco.bst

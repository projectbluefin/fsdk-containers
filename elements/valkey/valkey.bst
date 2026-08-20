kind: manual
description: Build valkey (Redis fork) from source for the distroless valkey server image.

sources:
  - kind: tar
    url: https://github.com/valkey-io/valkey/archive/refs/tags/%{valkey_version}.tar.gz
    ref: 7d7232acd1b8a49b4e05d07a00b3ca8c801ae06ab633ca6a3423bc5f385ab7ee

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/make.bst
  # valkey's Makefiles shell out to `sh -c 'uname -s'`, and the vendored
  # jemalloc's autoconf configure runs sed/grep/awk and coreutils (uname,
  # expr, tr, install) without checking for them. As with nginx
  # (elements/lab-runner/nginx.bst), declare every tool or the build fails
  # obscurely at dep-configure or link time.
  - freedesktop-sdk.bst:components/sed.bst
  - freedesktop-sdk.bst:components/grep.bst
  - freedesktop-sdk.bst:components/gawk.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  strip-binaries: ""
  # renovate: datasource=github-tags depName=valkey-io/valkey
  valkey_version: 9.1.1
  hardening-flags: ""
  (?):
    - arch == "x86_64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -fcf-protection=full"
    - arch == "aarch64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -mbranch-protection=standard"

config:
  build-commands:
    # deps/ vendors jemalloc, libvalkey (hiredis fork), lua, linenoise,
    # fpconv and hdr_histogram, all linked statically. FSDK has no jemalloc
    # or libvalkey component and its lua is not a drop-in for valkey's
    # patched fork, so building vendored is the upstream-tested configuration
    # and there is nothing sensible to swap out. MALLOC=jemalloc is the
    # upstream Linux default (fragmentation resistance for a long-running
    # cache process); keep it explicit so a future bump of upstream defaults
    # cannot silently change the allocator.
    - make -j%{max-jobs} MALLOC=jemalloc CFLAGS="%{hardening-flags}"

  install-commands:
    # make install honours PREFIX; binaries land in PREFIX/bin (merged-usr:
    # /usr/sbin is a symlink, so nothing may target sbin — see
    # elements/lab-runner/nginx.bst). USE_REDIS_SYMLINKS=no skips the
    # redis-server/redis-cli compatibility symlinks. A distroless server
    # image needs only valkey-server and valkey-cli (kubectl exec probes:
    # `valkey-cli ping`); sentinel mode is reachable as
    # `valkey-server /etc/valkey/sentinel.conf --sentinel`, so the
    # sentinel/check-* symlinks and the benchmark stay out.
    - make install PREFIX="%{install-root}/usr" USE_REDIS_SYMLINKS=no
    - |
      rm -f "%{install-root}/usr/bin/valkey-benchmark" \
            "%{install-root}/usr/bin/valkey-sentinel" \
            "%{install-root}/usr/bin/valkey-check-rdb" \
            "%{install-root}/usr/bin/valkey-check-aof"
    # /data is the working dir (rdb/aof); non-root wiring (65532:65532 +
    # /etc/passwd entry, issue #120) is Wave 3 — Kubernetes mounts a volume
    # here. An explicit `bind` directive keeps protected-mode on as
    # belt-and-braces while still accepting non-loopback clients.
    - mkdir -p "%{install-root}/etc/valkey" "%{install-root}/data"
    - |
      cat > "%{install-root}/etc/valkey/valkey.conf" <<'EOF'
      port 6379
      bind 0.0.0.0 -::*
      protected-mode yes
      dir /data
      appendonly no
      EOF

---
name: verify-distroless
description: Run and understand the distroless + slim verification gates. Use when validating an image before merge, debugging a failed gate, or adding a new gate.
metadata:
  context7-sources:
    - /apache/buildstream
---

# Verify Distroless

`just verify` is the merge contract. It builds nothing — it inspects the loaded
`ghcr.io/projectbluefin/<name>:latest` image. All gates must pass.

## The gates

1. **No shell binary in rootfs.** Exports the container filesystem and greps for
   `(ba)?sh` in the path list. The bash binary lives in FSDK's `runtime` domain
   (NOT `shells`), so it is removed by explicit `rm` in the SLIM recipe, not by a
   compose exclude. Using a tar listing avoids podman's exit-125 error on images
   with no CMD/ENTRYPOINT config — attempting `podman run --entrypoint /bin/sh`
   on such an image triggers `set -e` regardless of whether the shell exists.
2. **CA certificates present** — `etc/(ssl|pki)/.*(ca-bundle|cert)` in the rootfs.
3. **tzdata present** — `usr/share/zoneinfo/UTC`. A kept crash-preventer.
4. **Slim bloat removed** — fails if `terminfo` or any
   `lib{asan,tsan,lsan,ubsan,hwasan,gfortran}.so` reappears. Regression guard for
   the SLIM recipe.

## Run it

```
just verify
```

Rootless podman works; the recipe auto-detects and only uses `sudo` if `podman
info` fails.

## Debugging a failure

Export the rootfs and inspect directly:

```
cid=$(podman create ghcr.io/projectbluefin/<name>:latest)
podman export "$cid" | tar -tf - | grep -E '<thing you expect/don.t expect>'
podman rm "$cid"
```

A functional smoke test (loader + libc) on a distroless image — run a real binary,
not a shell:

```
podman run --rm ghcr.io/projectbluefin/<name>:latest /usr/bin/env
```

## Adding a gate

When you cut something in the SLIM recipe that must stay gone, add a matching
`grep` assertion to gate `[4/N]` in the `verify` recipe so the build fails if it
creeps back. Renumber the gate labels.

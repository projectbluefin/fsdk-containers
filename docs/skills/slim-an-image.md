---
name: slim-an-image
version: "1.0"
last_updated: 2026-08-08
id: slim-an-image
one_line_purpose: Shrink an OCI image by extending the shared SLIM recipe and proving the removal.
entry_point: docs/skills/slim-an-image.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [slim, size, distroless, optimization]
description: "The SLIM recipe — what to strip from an FSDK-carved image, the size levers, and their risk tiers. Use when shrinking an image or extending the shared slim block."
metadata:
  type: procedure
  context7-sources:
    - /apache/buildstream
    - /argoproj/argo-workflows
---

# Slim an Image

Use when an image is too large, or when extending the shared SLIM recipe.

## When to Use

Use when carving a smaller OCI image from FSDK, removing runtime bloat, or
adding a regression assertion for removed content.

## When NOT to Use

Do not use for the shell-enabled nspawn machine-image lane; its retained
development environment is deliberate. Do not replace a component-based image
with a package-manager overlay.

## Why a manual recipe

FSDK split-rule domains only cover:
`devel, debug, doc, sysconf, tests, shells, static-blocklist, license, locale,
vm-only, zoneinfo`. The largest **runtime-domain** bloat has *no domain* to exclude
it, so it must be removed explicitly with `rm` (in FSDK 25.08, this includes bash,
which lives in the `runtime` split domain; in FSDK 26.08+, `runtime-minimal` drops bash
and coreutils, moving them to `runtime-gnu`).
The shared commands live in `include/slim.yml` as BuildStream variables. Each
OCI element includes that fragment with `variables: (@): include/slim.yml` and
references either `%{slim-distroless-commands}` or
`%{slim-shell-enabled-commands}`. This keeps the lab-runner shell exception
explicit while preventing recipe drift.

## Applies to every image — not just glibc images

Even a "static" image (no glibc by design, e.g. one that only adds tzdata + CA
certs) **must run the full SLIM recipe**. Reason: `tzdata.bst` has a runtime dep on
`runtime-minimal`, which carries glibc, gcc runtimes (libasan, libtsan, libgfortran),
and terminfo into any compose that includes it. Skipping the SLIM recipe on a
"minimal" image will fail gate `[4/4]` of `just verify`.

Rule: include `include/slim.yml` in every new OCI script and choose the
appropriate shared command variable; do not copy/paste the recipe.

```
rm -rf _sizecheck
just bst artifact checkout <name>/<name>-runtime.bst --directory _sizecheck
du -sh _sizecheck && du -ah _sizecheck/usr | sort -rh | head -20
rm -rf _sizecheck
```

`_sizecheck` must be a project-relative path — the bst container only sees `/src`
(the repo). An absolute `/tmp/...` path is written inside the container and lost.

## Risk tiers

**Zero risk — always cut:**
- `usr/share/terminfo` (~12 MB) — terminal capability DB, useless in containers.
- gcc sanitizer runtimes `lib{asan,tsan,lsan,ubsan,hwasan}.so*` (~5 MB) — debug only.
- `libgfortran.so*` (~3.6 MB) — FORTRAN runtime pulled by gcc-libs.
- glibc `locale-archive`, `usr/share/i18n/charmaps` (~3 MB).
- leaked build tools: `localedef`, `sln`, `iconvconfig`, `ldconfig`, `pcre2test`.
- extra pcre2 widths `libpcre2-16/32`, `libpcre2-posix` (keep the 8-bit lib).

**Medium risk — trim, don't gut:**
- `gconv/` charset modules (~8 MB). Keep `gconv-modules*`, `UTF*`, `UNICODE*`,
  `ISO8859-1`, `ISO8859-15`, `CP1252`, `ANSI_X3.110`. Dropping a charset makes
  `iconv`/`.decode()` raise `LookupError` for that encoding (UTF-8 is built into
  glibc and always works).

**Do NOT cut (crash-preventers, cheap):**
- `tzdata` (`usr/share/zoneinfo`, ~2.6 MB) — python `zoneinfo` raises
  `ZoneInfoNotFoundError` without it. This is our differentiator vs suites that
  make you `pip install tzdata`.
- CA certificates + `usr/share/pki` trust source.
- `libstdc++`, `libgcc_s`, `libgomp` — C++ / OpenMP runtimes apps link.

## Prebuilt static binaries

Do not assume every upstream Go binary is already stripped, or that changing
versions will make it smaller. Inspect and measure each release artifact with
`file` and `stat`, then smoke-test the stripped copy before changing its element.
For example, Argo v4.0.8 contains debug data: GNU
`strip --strip-unneeded` reduces the amd64 CLI from 190,044,513 to 142,699,000
bytes while preserving its command surface. Argo v3.7.17 is nearly the same
size as v4 before and after stripping, so downgrading does not recover space.
kubectl v1.36.3 is already stripped and does not benefit from another pass.

Manual elements cannot rely on BuildStream's automatic stripping when
`freedesktop-sdk-stripper` is absent from the sandbox. Keep
`strip-binaries: ""`, add `freedesktop-sdk.bst:components/binutils.bst` as a
build dependency, and explicitly strip only artifacts whose measured size
decreases. Build dependencies do not enter the composed runtime image.

Keep a stripped CLI's execution check in `just verify`, using a local-only
subcommand. For `lab-runner`, invoke the binary directly with
`--entrypoint /usr/bin/argo` and `version --short`; the Argo CLI documents
`--short` as printing only its version. Check kubectl independently with
`kubectl version --client`, which avoids requiring a cluster. These checks
make a stripping regression fail the image contract rather than relying on a
one-time manual smoke test.

## Sandbox constraint

The oci-builder sandbox has **no `find`**. Use shell globs + `case`:

```sh
for g in "$L"/usr/lib/*/gconv; do
  [ -d "$g" ] || continue
  for f in "$g"/*; do
    case "${f##*/}" in
      gconv-modules*|UTF*|UNICODE*|ISO8859-1.so|ISO8859-15.so|CP1252.so|ANSI_X3.110.so) : ;;
      *) rm -f "$f" ;;
    esac
  done
done
```

## Lock it in

Add a regression assertion to `just verify` (the slim gates) for anything you
cut that must stay gone, so it fails the build if it creeps back.

## Core Process

1. Measure the artifact and identify the largest removable runtime content.
2. Reuse `include/slim.yml`; apply only the documented exception when required.
3. Build the affected image and run its `just verify` contract.
4. Add an assertion or executable smoke test for behavior that a removal or
   stripping step could regress.

## Common Rationalizations

- “The binary ran once locally.” A one-time check does not protect the next
  version bump; put the check in `just verify`.
- “Excluding `shells` removes bash.” Bash is in FSDK's runtime domain and must
  be explicitly removed for distroless images.
- “The build dependency is harmless.” Confirm it is build-only and absent from
  the composed runtime image.

## Red Flags

- Copying a SLIM command block instead of including `include/slim.yml`.
- Removing CA certificates, tzdata, or required charset modules to hit a size
  target.
- Stripping a prebuilt binary without a local-only execution test.
- Relaxing an image-size ceiling without measuring the old and new artifacts.

## Verification

- [ ] The element uses the component minimum, never `platform.bst`.
- [ ] `just validate`, the affected image build, and `just verify` pass.
- [ ] The image retains CA certificates, tzdata, and the required charset set.
- [ ] New stripping or removal behavior has a durable `just verify` regression
  check.

## Reference result

`base`: ~73 MB rootfs → **~40 MB image** after slim, all `just verify` gates green.

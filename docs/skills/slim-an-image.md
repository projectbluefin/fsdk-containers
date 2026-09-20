---
name: slim-an-image
version: "1.2"
last_updated: 2026-09-12
id: slim-an-image
one_line_purpose: Shrink an OCI image by extending the shared SLIM recipe and proving the removal.
entry_point: docs/skills/slim-an-image.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [slim, size, distroless, optimization, split-rules]
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

### A split domain does not necessarily contain what its name implies

This is the single most expensive assumption in this repo, and there are now **two confirmed
instances** — enough to treat as a rule rather than a quirk:

| You exclude | You expect gone | Actually still shipped |
| --- | --- | --- |
| `shells` | bash | bash — it lives in the `runtime` domain (documented in AGENTS.md) |
| `debug` | debug symbols | **~905 KB of separated DWARF, in every image** |

The second one is live today. Both `elements/base/base-runtime.bst` and
`elements/static/static-runtime.bst` list `debug` under `compose exclude:`, and these survive
it:

```
487551  usr/lib/debug/dwz/bootstrap/glibc.bst/x86_64-unknown-linux-gnu
417560  usr/lib/debug/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2.debug
```

Every base-derived image carries it (~2.3% of a ~45 MB
rootfs; `static` is not carved from `base`). Nothing at runtime reads separated DWARF, so it is a safe unconditional `rm`.

**The rule: never trust `compose exclude:` on its own — verify against the built rootfs.**

```console
$ podman export "$(podman create IMAGE)" | tar -tvf - | grep <what-you-excluded>
```

If a domain turns out to leak, the fix belongs in `include/slim.yml` as an explicit `rm`
alongside the other runtime-domain removals — **not** in the compose excludes, which have
already been shown not to hold. Pair it with a `just verify` gate: the existing "sanitizer/
fortran bloat must NOT be present" and "locale/build-tool bloat must NOT be present" gates
exist for exactly this reason, and a silent regression here is otherwise invisible.

## Applies to every image — not just glibc images

Even an image *intended* to be static (no glibc by design, e.g. one that only adds
tzdata + CA certs) **must run the full SLIM recipe**. Reason: `tzdata.bst` has a runtime dep on
`runtime-minimal`, which carries glibc, gcc runtimes (libasan, libtsan, libgfortran),
and terminfo into any compose that includes it. Skipping the SLIM recipe on a
"minimal" image will fail the slim gate of `just verify`.

This is not hypothetical: the repo's own `static` tier intended exactly that and **ships full
glibc anyway** — 88 shared objects, 15.9 MB compressed, differing from `base` by two files
(#116). Declaring a tier "static" in a description does not make it so. If you intend a
libc-free rootfs, you must compose the *produced files* (the cert bundle, zoneinfo) rather than
depend on the components, because `ca-certificates` pulls p11-kit and therefore glibc — and you
must verify the result with `tar -t`, not trust the element's own description.

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
- `usr/share/terminfo` (~12 MB unpacked, ~0.5 MB compressed) — kept since #101:
  without it a container must lie about the host TERM or vendor entries, both
  of which caused real color/rendering bugs downstream. `x/xterm-ghostty` is
  compiled in on top by `base/terminfo-ghostty.bst` (#105) — see
  `verify-distroless.md`.

## Prebuilt static binaries

Do not assume every upstream Go binary is already stripped, or that changing
versions will make it smaller. Inspect and measure each release artifact with
`file` and `stat`, then smoke-test the stripped copy before changing its element.
Measured on Argo v4.0.8 (current pin: v4.1.1): the release contains debug data,
and GNU `strip --strip-unneeded` reduced the amd64 CLI from 190,044,513 to
142,699,000 bytes while preserving its command surface. Argo v3.7.17 was nearly
the same size as v4 before and after stripping, so downgrading does not recover
space. kubectl v1.36.3 is already stripped and does not benefit from another pass.

Manual elements cannot rely on BuildStream's automatic stripping when
`freedesktop-sdk-stripper` is absent from the sandbox. Keep
`strip-binaries: ""`, add `freedesktop-sdk.bst:components/binutils.bst` as a
build dependency, and explicitly strip only artifacts whose measured size
decreases. Build dependencies do not enter the composed runtime image.

## Per-runtime-family recipes

The shared `include/slim.yml` carves the **OS layer** (shells, sanitizers, locale,
gconv, pcre) for every image. The **payload layer** — the interpreter, its
libraries, and the app's own footprint — is where most of a fat image's mass
lives, and it differs per runtime family. #130 established a family recipe for
each, measured, and generalised the reusable parts into `include/`.

> **Scope boundary (hold this line): remove only what cannot be used at runtime.**
> Anything that changes what the application *can do* is out of scope. A `jlink`
>ed JVM was tested and **failed** (`FindException: Module jdk.incubator.vector`,
> the module Lucene uses for SIMD vector search). Hand-picking modules removes
> capabilities silently and fails at *runtime*, not at build. The same rule
> forbids pruning Python `site-packages` by guesswork, tree-shaking
> `node_modules`, or dropping "unused" shared libraries. Measure, strip the
> provably-dead tail, prove it with a real smoke test — never re-architect.

### The family table

| Family | Strip (runtime-only) | Keep | Measured win | Images |
| --- | --- | --- | --- | --- |
| **JVM** | `jmods`, `ct.sym`, `src.zip`, `include/`, `man/`, JDK dev binaries (`javac`, `jshell`, `jdb`) | `java`, `keytool`, JRE runtime | 429 → 334 MB uncompressed, 243 → 158.6 MB gzip | opensearch, jre |
| **Python** | test suite, `ensurepip`, `tkinter`/`idlelib`, `lib2to3`, `pydoc_data`, `config-*`, `.a` archives | interpreter + stdlib, tzdata, CA certs | (see below) | python, cloud-custodian, in-toto |
| **Node** | devDependencies, bundled test suites, source maps, prebuilt binaries for other platforms | `node`, production `node_modules` | measure per image | node, kubestellar-hive |
| **Go** | confirm `-trimpath` / `-buildvcs=false`; strip symbols only if debuggability allows | the single static binary | usually already minimal | skopeo, buildah, lab-runner |
| **C daemons** | what FSDK split-rules already cover vs what leaks through the runtime domain | the daemon binary + its libs | check valkey/nginx/postgres/mariadb | valkey, nginx, postgres, mariadb |

The JVM and Python rows are the big levers — distribution choice + build-time
artifact removal measured at ~750 MB on the fat-image path (#130), dwarfing the
~40 MB FSDK-base-vs-AlmaLinux swap.

### The Python recipe is implemented

`catalog/python.yaml` now composes `include/slim-python.yml` (via
`slim.includes`), which defines `%{slim-python-commands}`. This is the first
family recipe lifted out of an inline `slim.extra` block and into `include/`.
It strips the Python test suite, `ensurepip` (+ pip/setuptools/wheel tail),
GUI front-ends, dead interpreter machinery, and static `.a` archives — the
interpreter and stdlib the app links are kept.

The next Python levers (`__pycache__/` bytecode caches, `pip`/`setuptools`/`wheel`
in `site-packages` where the app installs nothing at runtime, `.dist-info` extras,
vendored wheels) are **measured candidates, not yet applied** — each needs a
smoke test proving the target app's real functionality still runs first. They
are documented in the header comment of `include/slim-python.yml` so the work is
visible without a build.

### Where recipes live

Family recipes are `include/slim-<family>.yml` fragments, each defining a
`%{slim-<family>-commands}` variable. A record composes them with `slim.includes`
in its catalog record; the generator (scripts/generate_image_elements.py) emits
both `- include/<fragment>` in the element's `variables: (@)` and the
`%{slim-<family>-commands}` reference in `config.commands`, after the shared OS
recipe. This keeps the OS-level SLIM recipe shared and the payload-family
recipes per-family, without per-image copy/paste. A future family = a new
fragment + one line in `slim.includes`.

### Proving a strip is safe

Every family recipe needs a smoke test that exercises **real functionality**,
not just `--version`. The #130 jlink failure passed `--version` and would have
shipped broken. `catalog/python.yaml`'s smoke now imports the modules a container
Python runtime must support — `json`, `ssl`, `ctypes`, `sqlite3`, `zoneinfo` —
and prints the version, so a regression in the stripped stdlib fails the contract
(`just verify`) rather than the running app.

### Measurement methodology

A family recipe is not done until it ships with before/after numbers:

1. `just build` the image under test (`BUILD_IMAGE_NAME=<name> just build`).
2. Record uncompressed **and** gzip-compressed local podman size before and after
   the strip: `podman image inspect --format '{{.Size}}'` (uncompressed) plus
   `podman save | gzip -9 | wc -c` (transfer size). The JVM row's numbers above
   are the template.
3. Run `just verify` — the size ceiling and the family's smoke test must both
   pass. If the ceiling is the thing that bites, raise `size_ceiling_mib` in the
   record to the measured old size *before* stripping, never to the new one.
4. Lock the removal in a `just verify` gate (a forbidden-path/forbidden-name
   assertion) so the bloat cannot creep back on the next version bump.

### Compression — the remaining free bytes (needs a maintainer decision)

The stripped tree transfers cheaper under zstd than gzip. Measured on the
stripped Python/JVM trees: **zstd-19 ≈ 128 MB vs gzip ≈ 158.6 MB** — a further
~19% off transfer size, with no functional risk. Today every `elements/oci/*.bst`
sets `gzip: disabled` in `build-oci`, so the OCI output uses the oci-builder
default. zstd:chunked *can* be pushed (`just push-quay` already does), but
end-to-end support — registry, podman pull, and Kubernetes runtimes decompressing
zstd:chunked at startup — is not uniformly guaranteed, and the pull-latency win
at the kubelet is the unmeasured variable. **This is a maintainer decision, not
something to land blindly:** confirm the runtimes decompress zstd:chunked before
switching `build-oci` off its default. Until then, the recipe change stands on its
own uncompressed-size win.

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
- “Excluding `debug` removes the debug symbols.” It does not — ~905 KB of separated
  DWARF survives it in every image today. Verify the rootfs, not the element.
- “The `compose exclude:` list says it is gone, so it is gone.” Two domains have now
  been caught leaking. Confirm with `podman export | tar -tvf`.
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

`base`: ~73 MB rootfs → **~45 MB image** after slim (enforced ceiling: 64 MiB
uncompressed in `just verify`), all gates green.

# Slim an Image — Per-Runtime-Family Recipes

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

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

## The family table

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

## The Python recipe is implemented

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

## Where recipes live

Family recipes are `include/slim-<family>.yml` fragments, each defining a
`%{slim-<family>-commands}` variable. A record composes them with `slim.includes`
in its catalog record; the generator (scripts/generate_image_elements.py) emits
both `- include/<fragment>` in the element's `variables: (@)` and the
`%{slim-<family>-commands}` reference in `config.commands`, after the shared OS
recipe. This keeps the OS-level SLIM recipe shared and the payload-family
recipes per-family, without per-image copy/paste. A future family = a new
fragment + one line in `slim.includes`.

## Proving a strip is safe

Every family recipe needs a smoke test that exercises **real functionality**,
not just `--version`. The #130 jlink failure passed `--version` and would have
shipped broken. `catalog/python.yaml`'s smoke now imports the modules a container
Python runtime must support — `json`, `ssl`, `ctypes`, `sqlite3`, `zoneinfo` —
and prints the version, so a regression in the stripped stdlib fails the contract
(`just verify`) rather than the running app.

## Measurement methodology

A family recipe is not done until it ships with before/after numbers:

1. `just build` the image under test (`BUILD_IMAGE_NAME=<name> just build`).
2. Record uncompressed **and** gzip-compressed local podman size before and after
   the strip: `podman image inspect --format '{{.Size}}'` (uncompressed) plus
   `podman save | gzip -9 | wc -c` (transfer size). The JVM row's numbers above
   are the template.
3. Run `just verify` so the family's smoke test and content gates pass. Record
   the measured size in the PR body to make regressions visible during review.
4. Lock the removal in a `just verify` gate (a forbidden-path/forbidden-name
   assertion) so the bloat cannot creep back on the next version bump.

## Compression — the remaining free bytes (needs a maintainer decision)

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

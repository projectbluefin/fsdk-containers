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

## Upstream FSDK coverage we inherit

`fsdk-containers` never maintains its own package set. Images are composed from
FSDK `components/*` through the `freedesktop-sdk.bst` junction, so every artifact
we pull has already passed upstream Freedesktop-SDK's CI gates. Upstream's
GitLab pipeline (see `.gitlab-ci.yml` and `Makefile` in
`gitlab.com/freedesktop-sdk/freedesktop-sdk`) covers:

| Area | Upstream gate | What it proves |
|------|---------------|----------------|
| Static analysis / policy | `ruff format --check`, `ruff check`, `reuse lint`, `news_validator.py`, `flatpak_branch_validator.py`, `check-missing-components-stack.py` | Element definitions, licensing, and release metadata are consistent. |
| Build correctness | `make build` (`bst build tests/check-platform.bst tests/check-sdk.bst components.bst ...`) | The runtime, SDK, and component graph build and produce artifacts. |
| Debug / ABI / linkage | `make check-debuginfo`, `make check-abi`, `make check-rpath`, `make check-static-libraries`, `make check-dev-files` | Binaries have correct debug info, stable ABI, valid rpaths, and no leaked static libs or dev files. |
| Runtime integration | `make test-apps`, `make test-codecs`, `make test-ldd`, `make test-oci` | Real Flatpak apps, codecs, linker checks, and OCI layers run against the built runtime. |
| VM boot tests | `make run-vm` / `utils/test_minimal_system.py`, `utils/test_minimal_size.py` | Disk images boot in QEMU and do not grow unexpectedly. |
| CVE scanning | Scheduled `cve_report` job running `make generate-cve-report` | SDK, platform, and component manifests are checked against the NVD CVE database. |
| SBOM generation | `make generate-spdx-sbom-reports` (via `buildstream-sbom`) | Authoritative SPDX reports for platform/sdk/components. |
| Reproducibility | Weekly `reproducible_*` jobs running `buildstream-reprotest tests/reproducible-test.bst` | Two builds of the same element are bit-for-bit comparable with diffoscope. |
| Graph validation | `bst show --deps ...` | Dependency trees, versions, and element metadata are inspectable and valid. |

Because we consume upstream components through the FSDK junction and pull from
the shared GNOME/Bluefin BuildStream caches, all of the above coverage applies to
our base artifacts before we ever compose an OCI image.

## Local quality gates on top of upstream

`fsdk-containers` adds distroless-specific checks via `just verify`. For
distroless images (everything except the shell-enabled `lab-runner`):

1. **No shell binary in rootfs.** Exports the container filesystem and greps for
   `(ba)?sh` in the path list. The bash binary lives in FSDK's `runtime` domain
   (NOT `shells`), so it is removed by explicit `rm` in the SLIM recipe, not by a
   compose exclude.
2. **CA certificates present** — `etc/(ssl|pki)/.*(ca-bundle|cert)` in the rootfs.
3. **tzdata present** — `usr/share/zoneinfo/UTC`. A kept crash-preventer.
4. **Slim bloat removed** — fails if `terminfo`, sanitizer/Fortran runtimes,
   locale archives/charmaps, leaked locale/build tools, or extra PCRE2 widths
   reappear. Regression guard for the shared SLIM recipe.
5. **Image size ceiling** — compares Podman's uncompressed local `.Size` against
   a per-image ceiling with FSDK growth headroom. This is not compressed registry
   transfer size; it catches silent runtime-rootfs creep.

`lab-runner` is an explicit shell-enabled exception: it asserts that `bash` is
present and that `argo`, `just`, and `kubectl` are on disk.

## Graph validation

Before any image is built, `just validate` runs:

```
bst show --deps all oci/base.bst oci/static.bst ...
```

This is the local equivalent of upstream graph inspection: it resolves the
element graph, confirms the pinned FSDK junction and its overrides are valid,
and surfaces patch failures or renamed components immediately.

## Supply-chain attestations

After build and verify, CI adds supply-chain guarantees:

- **SBOM generation.** `just sbom <image>` (and `just sboms` for the whole suite)
  runs `buildstream-sbom` against the OCI element with `--deps all`, producing
  `<image>.spdx.json`. Because the image is distroless and has no package manager
  database, this BuildStream-native SBOM is the authoritative inventory of all
  FSDK components, point-release versions, and patch levels.
- **Keyless Sigstore signing.** `cosign sign -y` is run on the resolved multi-arch
  manifest-list digest. Signing uses GitHub Actions OIDC (`id-token: write`) via
  Fulcio; the certificate identity matches this repository's workflow path.
- **GitHub artifact attestation.** `actions/attest` signs provenance for the
  manifest-list digest and pushes it to the registry, independently verifiable
  with `gh attestation verify`.
- **SBOM attachment and signing.** The SPDX file is attached to the image with
  `oras attach` and the resulting referrer artifact is also `cosign sign`ed, so
  the whole image + metadata graph is cryptographically bound.

## Run it

```
just verify
```

Rootless podman works; the recipe auto-detects and only uses `sudo` if `podman
info` fails.

## Debugging a failure

Export the rootfs and inspect directly. Distroless images have no CMD or
ENTRYPOINT in their OCI config — `podman create` requires a placeholder command
to succeed (it does not validate whether the command exists in the image):

```
cid=$(podman create ghcr.io/projectbluefin/<name>:latest /nonexistent)
podman export "$cid" | tar -tf - | grep -E '<thing you expect/don.t expect>'
podman rm "$cid"
```

A functional smoke test (loader + libc) on a distroless image — run a real binary,
not a shell:

```
podman run --rm ghcr.io/projectbluefin/<name>:latest /usr/bin/env
```

## Adding test coverage

### When adding a new runtime component or image

Follow the three-element pattern in `add-new-image.md`, then extend coverage:

1. **Confirm upstream coverage.** Check that the component exists and is built/tested
   upstream:
   ```
   just bst show freedesktop-sdk.bst:components/<name>.bst
   ```
2. **Add a binary smoke test.** In the `verify` recipe, add a branch that executes
   the primary binary directly (e.g.
   `podman run --rm "$REF" nginx -v >/dev/null`). Distroless images have no shell,
   and `ldd` inside BuildStream's sandbox does not replicate the stripped container
   rootfs — execution is the only way to prove all dynamic dependencies survived
   `compose`.
3. **Set a size ceiling.** Add a `MAX_BYTES` case in the `verify` recipe for the new
   image. Calibrate it against uncompressed Podman sizes on **both** architectures
   and leave headroom for normal FSDK point-release growth.
4. **Register the SBOM variant.** Add the image to the `sbom` and `sboms` recipe
   case lists so CI generates and attaches an SPDX file.
5. **Document runtime-specific pruning.** If the new image needs extra `rm` steps
   beyond the shared SLIM recipe (e.g. Python stdlib tests), document *why* each
   removal is safe and add a matching `grep` negative assertion to `verify` so
   the gate fails if the bloat creeps back.
6. **Run the full local pipeline.**
   ```
   just validate && just build && just verify && just sbom <name>
   ```

### When adding a new FSDK series (e.g. `26.08`)

A new upstream minor line can rename components, restructure runtime stacks, or
change default package contents. Treat it as a coverage refresh:

1. **Update the junction.** Pin `elements/freedesktop-sdk.bst` to the new ref and
   run `just validate` to confirm the graph resolves and patches apply cleanly.
2. **Reconcile stack dependencies.** Review upstream release notes and `bst show`
   output for renames such as `public-stacks/runtime-minimal.bst` vs
   the FSDK stack that carries their shell tooling.
3. **Recalibrate size ceilings.** FSDK minor lines usually grow. Do not encode the
   exact current size; set ceilings with realistic headroom for the new series and
   both architectures.
4. **Re-run all smoke tests.** Execute every image's primary binary on `x86_64` and
   `aarch64`; a library that moved domains can pass `bst show` but still fail at
   runtime.
5. **Check tags and labels.** Run `just tags` and inspect the exported image labels
   (`io.projectbluefin.fsdk.version`, `io.projectbluefin.fsdk.ref`) to confirm they
   describe the new series correctly.
6. **Validate SBOM tooling.** If `buildstream-sbom` needs a newer pin for the new
   FSDK schema, update the pinned commit in the `sbom` recipe and the pip cache key
   in `.github/workflows/build.yml`.
7. **Watch upstream reports.** The upstream CVE, reproducibility, and SBOM reports
   for the new series are inherited automatically, but verify they are being
   published on the upstream branch before relying on them for a production tag.

## Adding a gate

When you cut something in the SLIM recipe that must stay gone, add a matching
`grep` assertion to gate `[5/N]` in the `verify` recipe so the build fails if it
creeps back. Renumber the gate labels. Keep the image size ceilings in the
`verify` recipe calibrated against both architecture builds; allow headroom for
normal FSDK point-release growth rather than encoding today's exact size.

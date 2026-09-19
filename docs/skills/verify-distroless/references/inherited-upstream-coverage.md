# Verify Distroless — Inherited Upstream Coverage

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

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

## Graph validation

Before any image is built, `just validate` enumerates every OCI image from
`elements/targets.json` plus `podman-vm/podman-vm-efi.bst` and runs
`bst show --deps all` over them. This is the local equivalent of upstream
graph inspection: it resolves the element graph, confirms the pinned FSDK
junction and its overrides are valid, and surfaces patch failures or renamed
components immediately.

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

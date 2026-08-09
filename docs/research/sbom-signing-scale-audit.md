# SBOM + Cosign Pipeline: Scale Audit

Research output resolving [#121](https://github.com/projectbluefin/fsdk-containers/issues/121). Parent map: [#113](https://github.com/projectbluefin/fsdk-containers/issues/113).

**No. A new image is not covered automatically, and the pipeline hard-fails on unknown names.**

Generic OCI export labels *are* automatic for an arbitrary `BUILD_IMAGE_NAME` — including both FSDK provenance labels. Everything else is gated by repeated literal image lists.

### Every per-image hardcoding point

| Location | What is hardcoded |
| --- | --- |
| `.github/workflows/build.yml:37-47` | CI build matrix — image list |
| `.github/workflows/build.yml:77-101` | Manifest / sign / SBOM / attestation matrix |
| `Justfile:124-127` | Graph validation list |
| `Justfile:157-165` | Per-image `DESC` |
| `Justfile:221-239` | Verify size ceilings (`*)` hard-fails) |
| `Justfile:260-333` | Per-image smoke / exception logic |
| `Justfile:525-538` | SBOM single-image name→element mapping |
| `Justfile:575-620` | Bulk SBOM literal list + duplicate mapping |
| `elements/oci/*.bst` | ~35 lines of duplicated OCI labels each (`base.bst:24-63`, `python.bst:36-69`, `buildah.bst:25-58`, `qemu-img.bst:28-61`, `lab-runner.bst:28-61`) |

An unlisted image is **never built by either CI matrix**, and `just sbom <new-image>` fails as unknown.

### Pipeline state

- **Cosign** is keyless GitHub OIDC. Signs the resolved **multi-arch index digest** once for the first published tag, and also signs the attached SBOM artifact. The workflow identity is generic to `build.yml`/ref, **not** image-specific — so signing itself scales fine. `build.yml:82-91,145-217`
- **SBOMs** are BuildStream-native SPDX 2.3 (`buildstream-sbom --deps all`), not Syft/Trivy, attached as OCI referrers (`application/vnd.spdx+json`) and then signed. `Justfile:525-572`, `build.yml:119-217`

### The provenance gap — this is the important one

FSDK labels are injected during **post-BuildStream Podman export**, while the SBOM is generated from the **BuildStream graph**. The two never meet, so the SBOM does **not** demonstrably carry `io.projectbluefin.fsdk.version` / `.ref`. `Justfile:167-181` vs `Justfile:525-572`

Worse for this catalog: prebuilt-binary elements already in the repo (`elements/lab-runner/argo.bst:12-25`, `kubectl.bst:10-21`, `just.bst:13-26`) carry URL + checksum, but **structured source-provenance attributes are not configured in `project.conf`** — no upstream signature, upstream image digest, SLSA provenance, or vendor attestation is captured.

**The catalog's entire value claim is provenance, and provenance is currently not in the SBOM.**

### Scale ceiling — a hard one

The checked-in OCI list is **seven** images, not eight.

- At **30** images: 60 arch builds + 30 manifest/SBOM/sign jobs = 90 OCI jobs, with 30 separate SBOM container runs each `pip install`ing `buildstream-sbom`.
- At **250** images: the build matrix expands to **500 jobs and exceeds GitHub Actions' 256-job matrix limit**. Not a slowdown — a wall.

### Required changes

1. **One machine-readable OCI catalog file** — name, element, architectures, verification profile, entrypoint/smoke command, metadata.
2. Generate both CI matrices and all validation/SBOM targets from it; delete every name→element case and literal list.
3. **Shard/batch builds per architecture before 128 images per arch.** Do not rely on one-image-per-matrix-cell.
4. Batch SBOM generation in one worker; install `buildstream-sbom` once.
5. Add explicit SBOM document/package metadata for FSDK version/ref, repo revision and final subject digest; configure and test BuildStream source-provenance attributes for ingested binaries.
6. Consolidate the duplicated OCI label block into a reusable `include/` template; keep only per-image declarative fields.
7. Replace size ceilings and smoke-test branches with catalog-declared verification profiles/baselines.

Items 1, 2, 6 and 7 are the substance of #119 and #122. Items 3-5 are new and have been graduated onto the map.

<sub>Sources: local `Justfile`, `.github/workflows/build.yml`, `project.conf`, `elements/oci/*.bst`, `README.md:55-72`; GitHub Actions usage limits.</sub>

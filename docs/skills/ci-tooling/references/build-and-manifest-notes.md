# CI Tooling — Build-time Deps and Manifest Annotations

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

## Build-time utility dependencies

Manual elements run their `config.install-commands` inside a minimal BuildStream sandbox. Declare every command used by those commands in `build-depends`; transitive availability from another element is not a contract. In particular, `gzip.bst` provides `gunzip`, while `bootstrap/coreutils.bst` provides `install`:

```yaml
build-depends:
  - freedesktop-sdk.bst:components/gzip.bst
  - freedesktop-sdk.bst:components/tar.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
```

Keep this explicit for downloaded binary elements such as the lab-runner CLI tools so both architectures build from a clean cache.

## Manifest Annotation Compatibility (GitHub Runners)

GHCR renders a package page from the image **index** annotations for
multi-arch images, and ArtifactHub reads the index as well — config labels on
the per-arch child manifests alone leave both blank (#97). The published index
must therefore carry the full `org.opencontainers.image.*` +
`io.artifacthub.package.*` label set as annotations, plus
`org.opencontainers.image.ref.name` set to the exact tag being pushed.

Runner podman is 4.9 (ubuntu-24.04): neither `podman manifest create
--annotation` nor `podman manifest annotate --index` exists there (index
annotations landed in podman 5.x), so do not reach for them. The manifest job
instead harvests the labels from the published per-arch image config
(`skopeo inspect --config`) and assembles the annotated index with:

```bash
docker buildx imagetools create -t "${REPO}:${TAG}" \
  --annotation "index:org.opencontainers.image.description=..." \
  "${REPO}-x86_64:${TAG}" "${REPO}-aarch64:${TAG}"
```

`docker buildx imagetools create` needs no builder instance and reuses the
GHCR credentials the job already writes to `~/.docker/config.json` via
`podman login --compat-auth-file`. The `index:` prefix targets the index
itself; a bare `key=value` would annotate every child manifest instead.

Use `oras attach --format json --no-tty` and capture `.digest` directly when you
need the SBOM referrer digest to sign, instead of selecting the first match from
`oras discover` output.

### Independent architecture asset publication

For raw VM assets, keep build, architecture-specific validation, and release
upload in the same matrix leg. A separate publish job with `needs` on a matrix
build or test job is an aggregate dependency: GitHub Actions waits for every
matrix leg before starting any publisher. This can strand a valid x86_64 asset
behind a slow or failed aarch64 build. The VM publisher must also retain the
point-release existence check so retries never overwrite an existing asset.

### Atomic release asset publication

Independent per-architecture publication means no job can make a
two-architecture release atomic, so the unit of atomicity is one
architecture's complete asset set and completeness across architectures is a
separate, loud check.

Facts this repository learned the hard way, from the `v25.08.15` release:

- A GitHub Release asset must be **under 2 GiB**. An oversized upload fails
  with `HTTP 422: Validation Failed ... size must be less than 2147483648`.
- `gh release upload TAG a b` is **not** atomic. Given a disk and its
  checksum in one invocation, the small checksum lands while the oversized
  disk is rejected. The command exits non-zero but the sidecar stays on the
  release: a checksum with no disk.
- Once that debris exists, a retry dies earlier still, with
  `asset under the same name already exists: [...]`, because an idempotency
  guard that only checks the disk name never notices the orphaned sidecar.
  The release stays wedged until someone deletes the asset by hand.

The rules that follow, implemented in `just publish-podman-vm`:

1. **Preflight.** Every file exists and is under the 2 GiB limit before
   anything is uploaded. Assets that cannot fit are compressed
   (`just compress-podman-vm`), never skipped.
2. **Rollback.** Record every asset uploaded by this invocation and delete
   them again on any later failure (`trap ... ERR`), so a failed run leaves
   the release exactly as it found it.
3. **Repair, without weakening immutability.** A complete asset set is never
   overwritten. A partial set is debris from a failed publish, not a
   published artifact: delete the orphans and republish the full set.
4. **Post-verify.** Re-read the release and require every expected name at
   its expected byte size, else roll back and fail.
5. **Cross-architecture completeness.** A `verify-release` job with
   `needs: build` and `if: always()` fails the run when the point-release tag
   is missing any asset for either architecture. Publication stays per leg;
   only the check is aggregate, so nothing is stranded.

Never paper over any of this with `continue-on-error`: a half-published
release looks like success to consumers and is worse than a clean failure.

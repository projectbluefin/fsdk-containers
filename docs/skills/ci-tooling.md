---
name: ci-tooling
description: >
  CI workflow conventions for fsdk-containers. Use when writing or editing
  .github/workflows/*.yml, debugging a failing build job, or adding a new
  CI step.
metadata:
  context7-sources:
    - /websites/github_en_actions
---

# CI Tooling

## When to Use

- Writing a new workflow or job
- Adding a new action dependency
- Debugging a CI failure in the build, verify, or manifest job

## When NOT to Use

- Debugging a BST build failure (see `bump-fsdk-version.md`)
- Debugging `just verify` gate logic (see `verify-distroless.md`)

## Org Conventions

### Action pins — always use SHA, never mutable tags

Every `uses:` line must reference a full commit SHA. Never use `@v2` or `@main`.

```yaml
# correct
- uses: taiki-e/install-action@ace6ebe54a6a0c86dfb5f7764b17f793b6925bc3 # v2

# wrong — mutable tag, supply-chain risk
- uses: taiki-e/install-action@v2
```

Check sibling repos (`projectbluefin/dakota`, `projectbluefin/common`) for the
current pinned SHA of any action before adding it.

### Installing `just` — taiki-e/install-action, not snap/cargo/apt

```yaml
- uses: taiki-e/install-action@ace6ebe54a6a0c86dfb5f7764b17f793b6925bc3 # v2
  with:
    tool: just
```

### `sudo` scope

Use rootless podman in build and verify jobs wherever possible. Only use `sudo
podman` when the step genuinely requires root (e.g. BST artifact cache access).
Do not mix `sudo podman` and plain `podman` within the same job — pick one
based on what the runner supports and stay consistent.

The `sudo_cmd` Just variable auto-detects at recipe startup:

```just
sudo_cmd := if `podman info >/dev/null 2>&1 && echo 1 || echo 0` == "1" { "" } else { "sudo" }
```

### Personal Access Tokens (PAT) Ban & Mergeraptor Bot
Personal Access Tokens (PATs) are strictly banned in this organization. To perform cross-repository operations, trigger other workflows, or write back to branches, always generate a GitHub App installation token using the **Mergeraptor** app:

```yaml
- name: Get mergeraptor token
  id: app-token
  uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3
  with:
    app-id: ${{ secrets.MERGERAPTOR_APP_ID }}
    private-key: ${{ secrets.MERGERAPTOR_PRIVATE_KEY }}
```

### Triggering Workflows (Pushes vs. Repository Dispatch)
Pushes made with the default `GITHUB_TOKEN` do **not** trigger other GitHub Actions workflows. To trigger downstream workflows or standard build runs from an automated update:
1. Push updates to an automated branch (e.g. `auto/update-fsdk`) and create a Pull Request using the Mergeraptor token.
2. Trigger the build workflow via a `repository_dispatch` event (e.g. `fsdk-updated`) using the Mergeraptor token as the authorization token.
3. Configure the build workflow's checkout step to accept a custom branch ref passed via `client_payload`:
   ```yaml
   - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
     with:
       ref: ${{ github.event.client_payload.ref || github.ref }}
   ```

## Workflow Structure

`build.yml` is a thin orchestrator; the two artifact classes live in their
own reusable workflows so a failure in one never blocks or obscures the
other in the Actions UI:

| File | Called by | Purpose |
|---|---|---|
| `build.yml` | GitHub triggers | `validate` + the pull-request build gate (`changed-targets`, `pr-build-oci`, `pr-build-vm-guest`), `matrix` (resolves the OCI image list once), fans out one `oci-images.yml` call per image, calls `vm-guest.yml`, then a `summary` job |
| `oci-images.yml` | `build.yml` via `workflow_call`, `image` input | `build` + `manifest` jobs for exactly one OCI distroless image |
| `vm-guest.yml` | `build.yml` via `workflow_call` | `build` job (matrix arch) for the podman-vm guest disk lane |
| `.github/actions/vm-boot-test` | `vm-guest.yml` and `build.yml` | composite action: install QEMU + UEFI firmware for one arch and run `tests/vm-boot.sh`, so the PR gate cannot drift from the release check |

Supporting workflows, none of which touch publication:

| File | Trigger | Purpose |
|---|---|---|
| `actionlint.yml` | PR/push touching `.github/workflows/**` or `.github/actions/**` | lints the pipeline itself |
| `validate-renovate.yml` | PR/push touching `renovate.json` | thin caller into `projectbluefin/actions` |
| `scorecard.yml` | weekly, push to `main`, branch-protection changes | OpenSSF Scorecard into code scanning |
| `vulnerability-scan.yml` | weekly, dispatch | Grype over the **published SPDX SBOM**, not the rootfs (see below) |
| `ghcr-cleanup.yml` | weekly, dispatch | prunes untagged manifests for this repo's packages only |
| `ci-alert.yml` | failed `Build images` push on `main` | reopens one CI alert issue with failed and skipped job links |
| `renovate.yml` | nightly, dispatch | Renovate, running with a Mergeraptor app token |
| `auto-update-fsdk.yml` | nightly, dispatch | FSDK bump branch + PR + verification dispatch |

| Job | Trigger | Purpose |
|---|---|---|
| `validate` (`build.yml`) | `pull_request` only | `bst show` element graph resolution, no build |
| `changed-targets` (`build.yml`) | `pull_request` only | `just changed-targets` against the merge base: which images and/or the VM guest this PR can break |
| `pr-build-oci` (`build.yml`) | `pull_request`, affected images only | build + `just verify` per affected image per architecture. No login, push, sign, or attest step exists in this job |
| `pr-build-vm-guest` (`build.yml`) | `pull_request`, when the VM guest is affected | build, checksum, and QEMU boot-test the guest disk. No release upload exists in this job |
| `matrix` (`build.yml`) | not on `pull_request` | reads `elements/targets.json` (`just image-matrix`) once and optionally narrows it to a validated manual-dispatch image |
| `oci-images` (`build.yml`) | after `matrix` | matrix-calls `oci-images.yml` once per selected image |
| `build` (`oci-images.yml`) | called for `push`/`workflow_dispatch`/`repository_dispatch` | matrix per architecture (x86_64 + aarch64) for that one image: build + verify + tag-push |
| `manifest` (`oci-images.yml`) | after that image's `build` matrix on `push`/`workflow_dispatch` | assemble and push the image's multi-arch manifest, sign, attach SBOM, publish GitHub provenance attestation |
| `build` (`vm-guest.yml`) | called for `push`/`workflow_dispatch`/`repository_dispatch` | matrix arch (x86_64 + aarch64): builds the `podman-vm-efi.bst` VM guest disk, converts it to QCOW2, checksums both, generates an SPDX SBOM, boot-tests the disk under plain QEMU (`tests/vm-boot.sh`, both architectures), then (only `push`/`workflow_dispatch`) publishes the raw disk + QCOW2 + checksums + SBOM as GitHub Release assets and attests them |
| `summary` (`build.yml`) | `always()`, not on `pull_request` | queries the Jobs API for the run and renders a target/status/duration table to the step summary |

The **canonical manifest** for the OCI image lane is `elements/targets.json`
(`oci_images` list). Adding a package means adding one entry there — `just
image-list`/`just image-matrix` are the only places that read it, and
`build.yml`'s `matrix` job, `just validate`, and `just sbom`/`sboms` all
derive their image lists from it. Nothing else hand-maintains a copy of the
image list.

`repository_dispatch` (used by the automated FSDK bump PR check) is
**verification-only**: it checks out the payload branch and runs both native
architecture builds plus `just verify`, but it must not log in, push per-arch
images, assemble manifests, sign, or publish attestations. This prevents
unreviewed bump branches from moving minor production tags. The
same caution applies to the VM guest's publish step: it only runs on
`push`/`workflow_dispatch`, never `repository_dispatch`.

### Main build alerts

`ci-alert.yml` listens for failed `Build images` push runs on `main`. It records
failed and skipped job links in one canonical `[CI] Build images failed on main`
issue, reopening it when a later failure occurs. Keep the workflow-level
concurrency group: without it, simultaneous failed runs can each observe no
open issue and create duplicates. It searches all issue states and reapplies
the `area/ci` and `priority/p1` labels whenever it reopens the issue.

### Per-image OCI fan-out

`build.yml` resolves `oci_images` only once, then uses a GitHub Actions matrix
to call `oci-images.yml` independently for each image. The reusable workflow
accepts one image name, so its `manifest` job waits only for that image's two
architecture legs. Never pass the whole target list into a reusable workflow
whose manifest job has `needs: build`: that makes every image's publication
wait for the slowest or failed unrelated matrix leg.

Manual `workflow_dispatch` exposes an optional `image` text input. An empty
value builds the whole canonical manifest; a non-empty value is validated
against `elements/targets.json` before it is fanned out. Targeted runs use a
separate parent concurrency group, while `oci-images.yml` serializes only
conflicting publication for the same ref and image. This lets distinct targets
run at the same time without racing their tags.

BuildStream's shared artifact and source pull caches in `project.conf` are the
CI cache layer for this fan-out. They are available to every native runner as
soon as it starts; a GitHub Actions local cache cannot provide artifacts to
sibling matrix jobs until the producing job finishes. Use a private remote CAS
for shared push caching, not a monolithic local cache, when public pull caches
are insufficient.

Source-verified against GitHub Actions: [Using a matrix strategy with a
reusable workflow](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#using-a-matrix-strategy-with-a-reusable-workflow)
and [Control concurrency of workflows and
jobs](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).

`brew-nspawn` (machine tarball) is not currently wired into any CI workflow
— see docs/skills/nspawn-machine-image.md. `podman-vm` (bootable VM disk) is
deliberately excluded from the OCI publishing matrix — see
docs/skills/vm-podman-guest.md for the VM guest's own build/test/publish
pipeline.

### The pull-request build gate

`just validate` only resolves the element graph. For a long time that was the
*only* thing a PR ran, so a PR could be green in 45 seconds while the merge
commit turned `main` red — which is exactly what happened, on push after push,
because the two failures (a `tar` ownership error in `lab-runner/just.bst` and
a QEMU TCG assertion on the aarch64 boot test) only existed in jobs that never
ran before merge.

Building all seven images on two architectures per PR is not viable, so the
gate is scoped by path ownership declared in `elements/targets.json`:

| Key | Meaning |
|---|---|
| `image_paths` | prefixes each image owns; touching one selects that image |
| `shared_paths` | project-wide files (`project.conf`, `include/`, the FSDK junction, `Justfile`, workflows) — these select `canary_image` instead of all seven |
| `canary_image` | the image every other image is carved from (`base`) |
| `vm_guest_paths` | selects the VM guest build + boot test |

`just changed-targets BASE HEAD` resolves them against the **merge base** and
prints `{"oci_images":[...],"vm_guest":bool}`. Run it locally to predict what a
branch will build. Add a new image's paths there in the same commit that adds
it to `oci_images`, or its PRs will silently build nothing.

**The PR jobs deliberately do not call `oci-images.yml` or `vm-guest.yml`.**
They are separate jobs with `permissions: contents: read` and no login, tag,
push, sign, attest, or release step anywhere in them. Gating publication with
an `if:` inside a shared job means one edit away from a fork PR publishing to
GHCR; gating it by *not having the code path* does not. Keep it that way.

### Automation tokens — everything that writes uses Mergeraptor

Neither a push nor a PR made with the default `GITHUB_TOKEN` triggers another
workflow. That is not a style point: Renovate ran with `github.token` while
`renovate.json` asked for non-major action bumps to be auto-merged, so bumps
could merge with **no checks having run at all**, and the nightly FSDK bump
branch was pushed the same way.

Every automated write — the FSDK bump branch push, its PR, its
`repository_dispatch`, and Renovate itself — mints a Mergeraptor installation
token. Mergeraptor is an org-level GitHub App whose permissions are already
granted, so this is a reuse of the existing `MERGERAPTOR_APP_ID` /
`MERGERAPTOR_PRIVATE_KEY` secrets: **never request a PAT, a new secret, or new
permissions for this.** Workflows that write only through that token drop their
own `permissions:` to `contents: read`.

Push with the token explicitly, because `persist-credentials: false` is now the
default for every checkout:

```bash
git push --force \
  "https://x-access-token:${GH_TOKEN}@github.com/${REPOSITORY}.git" \
  "HEAD:refs/heads/${BRANCH}"
```

`projectbluefin/actions` also ships `reusable-renovate.yml`, but it validates
its token with `check-token-health`'s `required_scopes: repo,workflow` — an
OAuth scope check a GitHub App installation token cannot satisfy. Until that
changes, this repo runs Renovate locally rather than reintroducing a PAT.

`platformAutomerge` is disabled in `renovate.json`: GitHub's auto-merge queue
needs branch protection this repo does not have, so Renovate merges on its own
check results. Major updates keep `automerge: false`.

### Scanning a distroless image

Do not add a rootfs vulnerability scanner. There is no RPM or dpkg database in
these images, so Grype/Trivy against the image ref report one package or none
(docs/skills/signing-and-sbom.md). `vulnerability-scan.yml` instead resolves
the manifest-list digest with `skopeo`, finds the SPDX referrer that the
publish pipeline attached with `oras discover --format json` (`.referrers[]`,
not `.manifests[]`), pulls it, and scans that. It reports; it never gates — a
CVE in an FSDK component is fixed by bumping FSDK, not by failing this repo.

### Required repository settings (admin, not in git)

The build gate only helps if merges are blocked when it fails, and `main`
currently has **no branch protection at all** (`GET /branches/main/protection`
returns 404). A repo admin needs to configure, once:

- Require a pull request before merging, with at least one approving review.
- Require status checks to pass, and mark these required:
  `validate`, `changed-targets`, `actionlint`, and the gate jobs
  (`pr-build-oci` / `pr-build-vm-guest` — both are skipped, and therefore
  green, when the diff does not affect them).
- Require branches to be up to date before merging (so the gate runs against
  what will actually land).
- Require linear history; block force pushes and deletions on `main`.

A merge queue is optional here. If one is enabled, note the caveat from
`projectbluefin/actions`' `reusable-renovate-automerge.yml`: queue entries
created by `github-actions[bot]` never dispatch required checks, so the queue
wedges unless the merge is performed with an app token.

Until protection exists, treat the gate as advisory: it will still turn a PR
red, but nothing stops a merge.

### Point-release tag immutability

FSDK point-release tags (e.g. `:25.08.13`) are immutable once published. Both
the Justfile `tag-push` recipe and the workflow manifest loop guard this with
a `skopeo inspect --no-tags docker://REPO:TAG` existence check and skip the
push if the tag exists.

The manifest job only runs after both required architectures (`x86_64` and
`aarch64`) have successfully built and published their staging images. It
requires both references before it can publish any tag, including an immutable
point release; a partial manifest is not a valid release. Do not add
`always()` to this job: it overrides GitHub Actions' default `needs: build`
success dependency and can promote a partial matrix. The manifest job resolves
the signing digest from the first tag it actually publishes, so signing is
skipped entirely when no tags are pushed.

The `podman-vm` release assets follow the same immutability shape one level
up: there is no rolling equivalent at all (GitHub Release assets
are inherently tied to their tag), and `just publish-podman-vm` guards
re-uploads with a `gh release view --json assets` existence check, skipping
an asset name that's already published on that tag instead of overwriting
it. See docs/skills/vm-podman-guest.md.

Set `fail-fast: false` on image and architecture matrices to prevent a single
container build failure from canceling unrelated container builds.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "It's just a minor version tag, supply-chain risk is low." | One compromised tag push owns every repo using it. Pin to SHA. |
| "I'll check what SHA other repos use later." | Check now — it's one `gh api` call and takes 10 seconds. |
| "`just validate` passes, the PR is fine." | Graph resolution is not a build. Every red `main` push in this repo's history was green at PR time for exactly this reason. |
| "Building on PRs is too expensive." | Building *everything* is. The gate builds only what the diff can break, and a shared-path change builds one canary. |
| "The publish step is skipped on PRs anyway." | An `if:` is one careless edit from being wrong. PR jobs have no publish code path at all. |
| "GITHUB_TOKEN is fine for the bot's push." | It cannot trigger workflows, so the resulting PR carries no checks — and Renovate was set to auto-merge those. |
| "Mergeraptor needs new permissions for that." | It is an org-level app; the permissions and secrets already exist. Reuse them. |

## Red Flags

- Any `uses:` line with a mutable ref (`@v2`, `@main`, `@latest`)
- `sudo podman` in one job and plain `podman` in another job doing the same operation
- A new action not present in any sibling repo — check upstream first
- A publish, sign, or release step reachable from a `pull_request` event
- An automated push, PR, or dispatch using `secrets.GITHUB_TOKEN` instead of a Mergeraptor token
- A new image added to `oci_images` without a matching `image_paths` entry — its PRs would build nothing
- `actions/checkout` without `persist-credentials: false` in a job that does not push
- A rootfs vulnerability scanner pointed at a distroless image ref

## Verification

- [ ] Every `uses:` line has a full 40-char SHA and a `# vX` comment
- [ ] `actionlint` passes (`actionlint` locally, or the `actionlint` workflow)
- [ ] `just verify` passes locally (or in CI) after workflow changes
- [ ] `just changed-targets <base> HEAD` selects the targets you expect
- [ ] No new mutable action refs introduced
- [ ] No new secret name: automation writes go through Mergeraptor

### GitHub artifact attestations

The manifest job uses the current GitHub `actions/attest` action with a
SHA-pinned ref. It requires `contents: read`, `packages: write`,
`attestations: write`, and `id-token: write`. The subject is the fully-qualified
repository name plus the resolved multi-arch `sha256:` digest, and
`push-to-registry: true` stores the attestation beside the image. Consumers can
verify it with `gh attestation verify oci://IMAGE:TAG -R ORG/REPO`.

The `podman-vm` guest disk has no OCI registry to attach to, so it uses the
same `actions/attest` action with `subject-path` (a glob over the `.raw`/
`.qcow2` files) instead of `subject-name`/`subject-digest`, and
`push-to-registry: false`. A second `actions/attest` call adds `sbom-path`
pointing at the `buildstream-sbom`-generated SPDX file to create a proper
GitHub SBOM attestation for the same subjects. Both are per-arch, matching
the "Independent architecture asset publication" pattern below.

Source-verified via Context7: `/websites/github_en_actions`.

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

Runner podman versions vary, and both `podman manifest annotate --index` and
`podman manifest create --annotation ...` may be unavailable depending on the
image. For maximum compatibility, keep manifest assembly to:

```bash
podman manifest create "${REPO}:${TAG}"
podman manifest add "${REPO}:${TAG}" "docker://${REPO}-x86_64:${TAG}"
podman manifest add "${REPO}:${TAG}" "docker://${REPO}-aarch64:${TAG}"
podman manifest push --all "${REPO}:${TAG}" "docker://${REPO}:${TAG}"
```

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

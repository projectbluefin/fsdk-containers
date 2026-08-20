# CI Tooling — Workflow Structure

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

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
| `publish-smoke` (`oci-images.yml`) | after `manifest` succeeds | native-runner pull of each architecture tag, OCI-config smoke execution, manifest signature verification, and SBOM referrer discovery |
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

When a reusable workflow job needs a repository/image string at the **job**
`env:` level, compose it directly from contexts allowed there (for example
`github`, `inputs`, `matrix`, `needs`, `vars`). Do **not** reference
`${{ env.* }}` inside `jobs.<job_id>.env`: GitHub validates that key before
runner startup, and an invalid context there can prevent the caller workflow
from instantiating any jobs at all.

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

`brew-nspawn` (machine tarball) is verified weekly and on demand by
`.github/workflows/brew-nspawn.yml`; it runs `just verify-brew` without
requiring a systemd host. `podman-vm` (bootable VM disk) is
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

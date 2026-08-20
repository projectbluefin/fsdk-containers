---
name: ci-tooling
version: "1.2"
last_updated: 2026-08-09
id: ci-tooling
one_line_purpose: Write and debug the GitHub Actions workflows that build and publish images.
entry_point: docs/skills/ci-tooling/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [ci, github-actions, workflows, publishing, scaling, attestation]
description: "CI workflow conventions for fsdk-containers. Use when writing or editing .github/workflows/*.yml, debugging a failing build job, adding a new CI step, or checking a change against the org-wide CI job budget."
metadata:
  type: reference
---

# CI Tooling

## When to Use

- Writing a new workflow or job
- Adding a new action dependency
- Debugging a CI failure in the build, verify, or manifest job
- Adding images to the catalog, or changing how many jobs a run fans out into

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

### Atomic BuildStream source updates

Only git repository sources with a commit-resolving datasource are Renovate-managed. The `buildah.bst` annotation uses Renovate's `git-refs` datasource and captures both `track:` and the matching `ref:` in one regex manager match. Renovate therefore updates the source selector and commit ref together. The manager's package name is the fully qualified GitHub URL (`https://github.com/{{depName}}.git`), as required by the `git-refs` datasource.

Archive and remote binary sources remain intentionally unautomated unless an authoritative upstream checksum manifest or verifiable signature can be integrated. Do not restore the old generic regex manager: a release version alone cannot identify or verify the exact archive artifact.

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

### The CI job budget — 60 concurrent jobs, org-wide

**The constraint is concurrency, not the 256-job matrix limit.** This trips people up because
the matrix limit is the documented number everyone quotes.

| Limit | Value | Raisable? |
|---|---|---|
| Job matrix | 256 jobs / workflow run | No |
| **Concurrent jobs, Team plan** | **60, shared across the whole org** | Yes, support ticket |
| Job execution time (GH-hosted) | 6 hours | No |
| Unique reusable workflows / top-level file | 50 (nesting 10 deep) | — |

`projectbluefin` is on the **Team** plan, so all 60 concurrent job slots are shared by every
repository in the org — not 60 per repo, and not 60 per workflow.

**Each OCI image costs 5 jobs**: `build` x2 arch, `manifest` x1, `publish-smoke` x2 arch. With
~5 jobs of non-OCI overhead per run (`matrix`, `summary`, `vm-guest`), a full catalog run
saturates the org at roughly **11 images**:

```
(60 - 5 overhead) / 5 jobs per image = 11 images
```

Failure here does not look like a failure. Jobs **queue** rather than error, so the symptom is
every other repo in the org waiting behind a catalog build, with nothing pointing at the cause.
Watch the job count, not just the red X.

Build time is not the constraint and has never been: the entire 7-image catalog builds serially
in ~40 minutes on `x86_64` (~29 on `aarch64`) against a 180-minute job timeout. Fan-out is
mostly scheduling overhead.

The agreed remedy (#127) is **sharding**: matrix entries are batches of 10 images, not single
images, giving `jobs = 5 x ceil(N / 10)`. The shard count is derived from
`elements/targets.json` in the `matrix` job, so adding image N+1 changes no workflow file.
Re-derive the batch size when any single image's build exceeds ~18 minutes.

When batching a loop over images, **do not `set -e` out of the loop.** Collect per-image
results, print one line per image, and exit non-zero at the end — otherwise one bad image hides
the other nine behind a single click.

### Debugging a failed job — check for artifacts before concluding "no logs"

`gh run view --log` / `--log-failed` show only what a step printed to stdout. Anything a job
uploads with `actions/upload-artifact` — captured serial consoles, core dumps, test output — is
**not in the logs** and must be downloaded separately:

```console
$ gh run view <run-id> --json jobs --jq '.jobs[] | select(.conclusion=="failure") | .name'
$ gh run download <run-id> -n <artifact-name>
```

This is not hypothetical. #110 (`podman-vm` guest fails its boot test under FSDK 26.08) sat
undiagnosed for ~12 hours with `main` red, recorded as *"CI logs for this job could not be
retrieved [...] without the captured serial console there was nothing to diagnose from"* — while
`vm-guest.yml` had been uploading `vm-boot-serial-<arch>` on every single failure. The whole
diagnosis was one `gh run download` away.

**Before writing "cannot reproduce" or "no logs available", list the run's artifacts.** If a job
captures diagnostic state on failure, say so in the failure message itself so the next person
does not have to know the artifact exists:

```console
FAIL: guest did not reach its ready point within 300s
      (serial console uploaded as artifact 'vm-boot-serial-x86_64')
```

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "It's just a minor version tag, supply-chain risk is low." | One compromised tag push owns every repo using it. Pin to SHA. |
| "I'll check what SHA other repos use later." | Check now — it's one `gh api` call and takes 10 seconds. |
| "`just validate` passes, the PR is fine." | Graph resolution is not a build. Every red `main` push in this repo's history was green at PR time for exactly this reason. |
| "Building on PRs is too expensive." | Building *everything* is. The gate builds only what the diff can break, and a shared-path change builds one canary. |
| "We're nowhere near the 256-job matrix limit." | 256 is the wrong number. 60 concurrent jobs, shared org-wide, binds ~23x earlier — at ~11 images. |
| "Adding one image only costs one job." | It costs **five**: build x2, manifest, publish-smoke x2. |
| "CI is slow, so shrink the build." | Measure first. The full catalog builds in 40 min/arch; the cost is job scheduling, not compilation. |
| "The build didn't fail, so we're within limits." | Exceeding concurrency queues jobs, it doesn't fail them. The damage lands on other repos in the org. |
| "The publish step is skipped on PRs anyway." | An `if:` is one careless edit from being wrong. PR jobs have no publish code path at all. |
| "GITHUB_TOKEN is fine for the bot's push." | It cannot trigger workflows, so the resulting PR carries no checks — and Renovate was set to auto-merge those. |
| "Mergeraptor needs new permissions for that." | It is an org-level app; the permissions and secrets already exist. Reuse them. |
| "The logs are empty, so there is nothing to diagnose." | Check `gh run download`. Artifacts are not in the logs, and #110 stalled 12 hours on exactly this. |

## Red Flags

- Any `uses:` line with a mutable ref (`@v2`, `@main`, `@latest`)
- `sudo podman` in one job and plain `podman` in another job doing the same operation
- A new action not present in any sibling repo — check upstream first
- A publish, sign, or release step reachable from a `pull_request` event
- An automated push, PR, or dispatch using `secrets.GITHUB_TOKEN` instead of a Mergeraptor token
- A new image added to `oci_images` without a matching `image_paths` entry — its PRs would build nothing
- A change that multiplies jobs per image — check it against the 60-job org-wide budget first
- A loop over images that runs under `set -e` — the first failure masks every image after it
- `actions/attest` with `push-to-registry: true` given anything but one subject
- A documented `gh attestation verify` command with no `--signer-workflow`/`--signer-repo`
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
`push-to-registry: true` stores the attestation beside the image.

Consumers verify with:

```console
$ gh attestation verify oci://IMAGE:TAG -R projectbluefin/fsdk-containers \
    --signer-repo projectbluefin/fsdk-containers
```

**The signer flag is not optional here.** Our images are attested from the *reusable* workflow
`oci-images.yml`, and `gh attestation verify` documents that when an attestation is generated
via a reusable workflow, that reusable workflow is the signer — so `--signer-workflow` or
`--signer-repo` must be supplied. A bare `-R ORG/REPO` fails against these images.

#### `push-to-registry` takes a single subject only

`actions/attest` states that `push-to-registry` "requires that the resolved subject is a
**single** fully-qualified OCI image reference with a SHA-256 digest". GitHub Actions has **no
step-level loop**, so a job that handles N images cannot call `actions/attest` N times, and
cannot pass N subjects while also pushing to the registry. This constrains any batching of the
publish path (see the job budget above).

The way through is `subject-checksums` — many subjects, one attestation — with
`push-to-registry: false`. Verification survives, because `gh attestation verify` **fetches via
the GitHub API by default**; pulling from the registry instead is the opt-in `--bundle-from-oci`
path. What is lost is the attestation-as-registry-referrer for consumers who pass that flag.

By contrast, the SPDX SBOM referrer is plain `oras attach` + `cosign sign` in shell, so it
batches by simply looping. Cosign signing also scales without per-image configuration: a generic
OIDC identity over the index digest.

The `podman-vm` guest disk has no OCI registry to attach to, so it uses the
same `actions/attest` action with `subject-path` (a glob over the `.raw`/
`.qcow2` files) instead of `subject-name`/`subject-digest`, and
`push-to-registry: false`. A second `actions/attest` call adds `sbom-path`
pointing at the `buildstream-sbom`-generated SPDX file to create a proper
GitHub SBOM attestation for the same subjects. Both are per-arch, matching
the "Independent architecture asset publication" pattern below.

Source-verified via Context7: `/websites/github_en_actions`.

## Reference material

- [`references/workflow-structure.md`](references/workflow-structure.md) — CI Tooling — Workflow Structure
- [`references/build-and-manifest-notes.md`](references/build-and-manifest-notes.md) — CI Tooling — Build-time Deps and Manifest Annotations

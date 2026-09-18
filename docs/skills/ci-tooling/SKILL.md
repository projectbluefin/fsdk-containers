---
name: ci-tooling
version: "1.4"
last_updated: "2026-09-18"
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
- uses: taiki-e/install-action@16b05812d776ae1dfaabc8277e421fb6d2506419 # v2

# wrong — mutable tag, supply-chain risk
- uses: taiki-e/install-action@v2
```

Check sibling repos (`projectbluefin/dakota`, `projectbluefin/common`) for the
current pinned SHA of any action before adding it.

### Installing `just` — taiki-e/install-action, not snap/cargo/apt

```yaml
- uses: taiki-e/install-action@16b05812d776ae1dfaabc8277e421fb6d2506419 # v2
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

`renovate.json` has one `custom.regex` manager driven by `# renovate:
datasource=... depName=...` annotations in `.bst` files and the Justfile. For
`git_repo` sources the annotation sits on `track:` (e.g. `buildah.bst`:
`datasource=github-tags depName=containers/buildah`); Renovate bumps the tag,
then `refresh-bst-refs.yml` re-runs `bst source track` on the PR branch to
write the matching commit `ref:` — neither tool does both halves alone. See
`track-upstream-versions.md` for the full contract.

Archive and remote binary sources pin a sha256 `ref:` refreshed by the same
workflow. Do not restore the old generic regex manager: a release version
alone cannot identify or verify the exact archive artifact.

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

The org-wide CI job budget (60 concurrent jobs, and the sharding remedy if it
binds) and how to recover diagnostic artifacts from a failed run now live in
[`references/job-budget-and-triage.md`](references/job-budget-and-triage.md).

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

The manifest job uses SHA-pinned `actions/attest` with `contents: read`,
`packages: write`, `attestations: write`, `id-token: write`; the subject is the
fully-qualified repo name plus resolved multi-arch digest, pushed to the
registry. For the gotchas that constrain CI authoring — mandatory
`--signer-repo` on verify (reusable-workflow signer), `push-to-registry`'s
single-subject limit vs. the `subject-checksums` escape hatch, and the VM
disk's `subject-path` pattern — see
[signing-and-sbom.md](../signing-and-sbom.md). The single-subject limit is why
any batching of the publish path must loop `oras`/`cosign` in shell instead
(see [the job budget](references/job-budget-and-triage.md)).

## Reference material

| Reference | What is in it |
| --------- | ------------- |
| [`references/workflow-structure.md`](references/workflow-structure.md) | Workflow file map (`build.yml`, `oci-images.yml`, `vm-guest.yml`), main-build alerts, per-image OCI fan-out, the pull-request build gate, Mergeraptor automation tokens, distroless scanning, the admin-only repo settings, and point-release tag immutability. |
| [`references/build-and-manifest-notes.md`](references/build-and-manifest-notes.md) | Build-time utility dependencies, and manifest annotation compatibility on GitHub runners including independent and atomic release-asset publication. |
| [`references/job-budget-and-triage.md`](references/job-budget-and-triage.md) | The 60-concurrent-job org-wide CI budget, what each image costs, the sharding remedy, and finding the artifacts a failed run uploaded but never printed to the log. |

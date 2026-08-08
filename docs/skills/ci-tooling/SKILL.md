---
name: ci-tooling
version: "1.0"
last_updated: 2026-08-08
id: ci-tooling
one_line_purpose: Write and debug the GitHub Actions workflows that build and publish images.
entry_point: docs/skills/ci-tooling/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [ci, github-actions, workflows, publishing]
description: "CI workflow conventions for fsdk-containers. Use when writing or editing .github/workflows/*.yml, debugging a failing build job, or adding a new CI step."
metadata:
  type: reference
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

## Reference material

- [`references/workflow-structure.md`](references/workflow-structure.md) — CI Tooling — Workflow Structure
- [`references/build-and-manifest-notes.md`](references/build-and-manifest-notes.md) — CI Tooling — Build-time Deps and Manifest Annotations

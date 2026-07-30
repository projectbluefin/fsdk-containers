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

| Job | Trigger | Purpose |
|---|---|---|
| `validate` | `pull_request` only | `bst show` element graph resolution, no build |
| `build` | `push`, `workflow_dispatch` | matrix per container (base, static, skopeo, lab-runner, python, buildah, qemu-img) and arch (x86_64 + aarch64), build + verify + tag-push |
| `manifest` | after `build` succeeds on `push`/`workflow_dispatch` | same container matrix, assemble and push multi-arch manifest, sign, attach SBOM, publish GitHub provenance attestation |
| `build-podman-vm` | not on `pull_request` | matrix arch (x86_64 + aarch64), builds the `podman-vm-efi.bst` VM guest disk (not an OCI image), uploads the raw disk + checksum manifest as a workflow artifact per arch |
| `test-podman-vm` | after `build-podman-vm`, not on `pull_request` | x86_64 only: downloads that raw disk and runs the `tests/podman-vm.sh` QEMU/Lima boot integration test |
| `publish-podman-vm` | after `build-podman-vm` **and a passing** `test-podman-vm`, only `push`/`workflow_dispatch` | matrix arch (x86_64 + aarch64), uploads the raw disk + checksum manifest as immutable GitHub Release assets under the `v<fsdk_version>` tag — never a mutable `latest` URL |

`repository_dispatch` (used by the automated FSDK bump PR check) is
**verification-only**: it checks out the payload branch and runs both native
architecture builds plus `just verify`, but it must not log in, push per-arch
images, assemble manifests, sign, or publish attestations. This prevents
unreviewed bump branches from moving `latest` or minor production tags. The
same caution applies to `publish-podman-vm`: it only runs on `push`/
`workflow_dispatch`, never `repository_dispatch`.

The container matrix is the publishing contract: every OCI image in
`elements/oci/` that ships to GHCR must appear in **both** matrices, in
`just validate`, and in the `just sbom`/`sboms` case lists. `brew-nspawn`
(machine tarball) and `podman-vm` (bootable VM disk) are deliberately
excluded from the OCI publishing matrix — see docs/skills/vm-podman-guest.md
for the VM guest's own separate publish/test pipeline.

### Point-release tag immutability

FSDK point-release tags (e.g. `:25.08.13`) are immutable once published. Both
the Justfile `tag-push` recipe and the workflow manifest loop guard this with
a `skopeo inspect --no-tags docker://REPO:TAG` existence check and skip the
push if the tag exists.

`latest` and the minor-line tag are rolling, but the manifest job only
assembles and pushes them when **both** required architectures (`x86_64` and
`aarch64`) were successfully built and published. If one architecture failed,
the rolling/minor-line tags are skipped so a single-arch manifest cannot
overwrite the existing multi-arch manifest. The manifest job resolves the
signing digest from the first tag it actually publishes, so signing is skipped
entirely when no tags are pushed.

The `podman-vm` release asset follows the same immutability shape one level
up: there is no rolling `latest` equivalent at all (GitHub Release assets
are inherently tied to their tag), and `just publish-podman-vm` guards
re-uploads with a `gh release view --json assets` existence check, skipping
an asset name that's already published on that tag instead of overwriting
it. See docs/skills/vm-podman-guest.md.

Set `fail-fast: false` on the multi-dimensional matrices to prevent a single container build failure from canceling the other container builds.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "It's just a minor version tag, supply-chain risk is low." | One compromised tag push owns every repo using it. Pin to SHA. |
| "I'll check what SHA other repos use later." | Check now — it's one `gh api` call and takes 10 seconds. |

## Red Flags

- Any `uses:` line with a mutable ref (`@v2`, `@main`, `@latest`)
- `sudo podman` in one job and plain `podman` in another job doing the same operation
- A new action not present in any sibling repo — check upstream first

## Verification

- [ ] Every `uses:` line has a full 40-char SHA and a `# vX` comment
- [ ] `just verify` passes locally (or in CI) after workflow changes
- [ ] No new mutable action refs introduced

### GitHub artifact attestations

The manifest job uses the current GitHub `actions/attest` action with a
SHA-pinned ref. It requires `contents: read`, `packages: write`,
`attestations: write`, and `id-token: write`. The subject is the fully-qualified
repository name plus the resolved multi-arch `sha256:` digest, and
`push-to-registry: true` stores the attestation beside the image. Consumers can
verify it with `gh attestation verify oci://IMAGE:TAG -R ORG/REPO`.

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

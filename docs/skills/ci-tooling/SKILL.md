---
name: ci-tooling
version: "1.5"
last_updated: 2026-09-25
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
- Debugging `just verify` gate logic (see `verify-distroless/SKILL.md`)

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

Use the bare form above in this repo and in every non-fork repo: the action
resolves the installation through `GET /repos/{owner}/{repo}/installation`, so
the token is scoped to the calling repository alone.

#### Forked repositories — pass `owner:` or the mint 404s

In a **fork**, that same resolution returns
`Not Found - get-a-repository-installation-for-the-authenticated-app` and the
step dies — `actions/create-github-app-token` retries only 5xx and network
errors, so a 404 fails on the first attempt.

The **app is not missing**: `mergeraptor[bot]` is already opening Renovate PRs
in those repos, and `projectbluefin/renovate-config` mints successfully against
them because it passes `owner:`. What fails is the per-repository lookup —
GitHub resolves it through the fork's upstream network (`OpenPrinting/*`, where
this app is not installed), which the owner-level lookup never consults. It
took down `update-base.yml` in all four projectbluefin printer-app forks
(hplip, gutenprint, ghostscript, ps) — #331. **Check for a fork before
escalating to an org admin**; there is usually nothing for them to fix.

Pass `owner:` **instead of** `repositories:`:

```yaml
- name: Mint mergeraptor token
  id: app-token
  uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
  with:
    app-id: ${{ secrets.MERGERAPTOR_APP_ID }}
    private-key: ${{ secrets.MERGERAPTOR_PRIVATE_KEY }}
    owner: ${{ github.repository_owner }}
    # `owner:` widens the token to every repo in the installation, so take
    # back with permission-* what the job does not need.
    permission-contents: write
    permission-pull-requests: write
```

`owner:` alone switches the action to
`GET /users/{username}/installation` (works for orgs), which is the only path
that resolves in a fork. **`owner:` + `repositories:` does not help**: with
both set the action is back on the per-repository endpoint, so it 404s the
same way. `owner:` alone returns a token for the whole installation —
`permission-*` inputs are what keep it from being a blank cheque.
`projectbluefin/renovate-config` uses this form and writes into the forks
successfully.

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

### Regenerating `.github/requirements` hashes

Four steps install `.github/requirements/verify.txt`, always the same way:

```yaml
run: python3 -m pip install --user --require-hashes --only-binary=:all: -r .github/requirements/verify.txt
```

`--only-binary=:all:` is not decoration. If a requirement lists only its sdist
hash, pip picks the sdist — the one link whose hash is allowed — and builds it,
and build isolation then downloads ~11 unpinned, unhashed build backends
(hatchling, setuptools-scm, trove-classifiers, ...) that execute arbitrary code
inside `oci-images.yml`'s verify job, which holds `packages: write`,
`attestations: write` and `id-token: write`. So every requirement carries its
**wheel** hash, and the flag makes an sdist fallback impossible even if a wheel
hash is ever dropped.

The `custom.regex` manager in `renovate.json` rewrites only the `==` version,
never the hashes, so **every Renovate bump of this file arrives with stale
hashes and a red install step**. That is pip failing closed, not a bug — but it
means the reviewer regenerates before merging:

1. Re-resolve the transitive closure in a throwaway venv. A bump can add or
   drop a dependency and `--require-hashes` needs the *whole* closure:

   ```console
   $ python3 -m venv /tmp/reqgen
   $ /tmp/reqgen/bin/pip install -q "pyyaml==<new>" "jsonschema==<new>"
   $ /tmp/reqgen/bin/pip freeze
   ```

2. Emit one line per requirement from the PyPI JSON API. The committed
   selection is `py3-none-any` wheels + `manylinux` wheels + the sdist: the
   runners are `ubuntu-24.04` / `ubuntu-24.04-arm` (glibc), so musllinux,
   macOS and Windows wheels are deliberately excluded.

   ```console
   $ python3 - <<'EOF'
   import json, urllib.request
   PINS = [("pyyaml", "6.0.3"), ("jsonschema", "4.26.0")]  # from pip freeze
   for pkg, ver in PINS:
       urls = json.load(urllib.request.urlopen(
           f"https://pypi.org/pypi/{pkg}/{ver}/json"))["urls"]
       hashes = [u["digests"]["sha256"] for u in urls
                 if u["filename"].endswith(("-none-any.whl", ".tar.gz"))
                 or "manylinux" in u["filename"]]
       print(f"{pkg}=={ver} " + " ".join(f"--hash=sha256:{h}" for h in hashes))
   EOF
   ```

3. Prove the result resolves to wheels only:

   ```console
   $ /tmp/reqgen/bin/pip download --no-deps --require-hashes --only-binary=:all: \
       -r .github/requirements/verify.txt -d /tmp/reqcheck
   $ ls /tmp/reqcheck   # every entry must be a .whl, never a .tar.gz
   ```

Do not hand-patch one hash out of the Renovate diff. Regenerate the whole line:
a version bump changes every per-platform wheel hash, not just one.

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

Today the `matrix` job resolves `oci_images` from `elements/targets.json` and
the build fans out **one reusable call per image** — adding image N+1 changes
no workflow file. The agreed remedy (#127) if the budget binds is **sharding**:
matrix entries become batches of ~10 images, giving `jobs = 5 x ceil(N / 10)`.
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
| "The mint 404s, so an org admin must grant the app access to this repo." | Check whether the repo is a fork first. In a fork the app already has access and `mergeraptor[bot]` is probably already opening PRs there — the failing thing is the per-repository *lookup*. Pass `owner:` (above) before escalating to an admin. |
| "The logs are empty, so there is nothing to diagnose." | Check `gh run download`. Artifacts are not in the logs, and #110 stalled 12 hours on exactly this. |
| "`--require-hashes` already locks the install down." | Only against the artifacts you hashed. An sdist-only hash makes pip *build* the package, pulling ~11 unpinned build backends into a `packages: write` job. Hash the wheel and pass `--only-binary=:all:`. |

## Red Flags

- Any `uses:` line with a mutable ref (`@v2`, `@main`, `@latest`)
- `sudo podman` in one job and plain `podman` in another job doing the same operation
- A new action not present in any sibling repo — check upstream first
- A publish, sign, or release step reachable from a `pull_request` event
- An automated push, PR, or dispatch using `secrets.GITHUB_TOKEN` instead of a Mergeraptor token
- A `create-github-app-token` step in a **forked** repo with no `owner:` — the mint 404s on the per-repository installation lookup, and 404 is not retried
- A new image added to `oci_images` without a matching `image_paths` entry — its PRs would build nothing
- A change that multiplies jobs per image — check it against the 60-job org-wide budget first
- A loop over images that runs under `set -e` — the first failure masks every image after it
- `actions/attest` with `push-to-registry: true` given anything but one subject
- A documented `gh attestation verify` command with no `--signer-workflow`/`--signer-repo`
- `actions/checkout` without `persist-credentials: false` in a job that does not push
- A rootfs vulnerability scanner pointed at a distroless image ref
- A `pip install` of `.github/requirements/*.txt` without `--require-hashes --only-binary=:all:`
- A requirement in `.github/requirements/*.txt` whose only hash is its `.tar.gz`
- A CI-input path (`.github/requirements/**`, the workflow file itself) missing from a workflow's `paths:` filter — the PR that changes it runs nothing

## Verification

- [ ] Every `uses:` line has a full 40-char SHA and a `# vX` comment
- [ ] `actionlint` passes (`actionlint` locally, or the `actionlint` workflow)
- [ ] `just verify` passes locally (or in CI) after workflow changes
- [ ] `just changed-targets <base> HEAD` selects the targets you expect
- [ ] No new mutable action refs introduced
- [ ] No new secret name: automation writes go through Mergeraptor
- [ ] `pip download --no-deps --require-hashes --only-binary=:all: -r .github/requirements/verify.txt -d <tmp>` yields only `.whl` files

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
(see the job budget above).

## Reference material

- [`references/workflow-structure.md`](references/workflow-structure.md) — CI Tooling — Workflow Structure
- [`references/build-and-manifest-notes.md`](references/build-and-manifest-notes.md) — CI Tooling — Build-time Deps and Manifest Annotations

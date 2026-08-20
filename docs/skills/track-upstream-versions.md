---
name: track-upstream-versions
version: "1.0"
last_updated: 2026-08-20
id: track-upstream-versions
one_line_purpose: Keep every non-FSDK upstream package pinned at its latest release automatically.
entry_point: docs/skills/track-upstream-versions.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [renovate, versioning, buildstream, dependencies]
description: "Keep every non-FSDK upstream package current automatically. Use when adding software to an image, or when a pin has drifted behind upstream."
metadata:
  type: runbook
  context7-sources:
    - /websites/renovatebot
    - /apache/buildstream
---
# Track Upstream Versions

## The rule

**Nothing in this repo may sit behind upstream.** Every non-FSDK package is pinned in a
BuildStream element, and every one of those pins is discovered by Renovate and refreshed
automatically. If upstream releases it, we want it.

FSDK itself is not covered here — its junction is tracked by
`.github/workflows/auto-update-fsdk.yml`. See [bump-fsdk-version.md](bump-fsdk-version.md).

## Why this needs two mechanisms

A BuildStream pin is always a **pair**: a human-readable version and an integrity `ref:`.

```yaml
variables:
  # renovate: datasource=github-releases depName=casey/just
  just_version: 1.58.0          # <- Renovate updates this
sources:
  - kind: remote
    url: "https://github.com/casey/just/releases/download/%{just_version}/..."
    ref: 4a5cc2f53e6f...        # <- Renovate CANNOT compute this
```

Renovate discovers versions but cannot compute a sha256 of a tarball it never downloads.
`bst source track` computes refs but cannot discover a new version behind a variable-built
URL. **Neither tool can do this alone**, so we run both:

| Step | Tool | Does |
|---|---|---|
| 1. Discover | Renovate custom manager | Bumps the version, opens a PR |
| 2. Refresh | `.github/workflows/refresh-bst-refs.yml` | Runs `bst source track` on the changed elements, pushes the corrected `ref:` back onto the PR branch |
| 3. Prove | `build.yml` | `just verify` must pass before merge |

For `kind: git_repo` sources, `bst source track` resolves `track:` to a commit, so step 2
covers those too.

## When the refresh workflow is skipped (manual repair)

`refresh-bst-refs.yml` only acts when its job gate matches the PR author. If the gate
drifts from reality, the job reports **skipped** and the Renovate PR keeps a stale `ref:`,
failing CI with:

```
FAILURE ... File downloaded from <url> has sha256sum '<actual>', not '<pinned>'!
```

Known instance: Renovate here authenticates through the Mergeraptor GitHub App, so its PRs
are authored by `mergeraptor[bot]` while the workflow originally gated on `renovate[bot]`
— every run silently skipped until the gate was fixed. Diagnose before hand-fixing:

```
gh run list --workflow=refresh-bst-refs.yml --limit 20   # "skipped" on the renovate PR = gate miss
```

Manual repair is exactly what `bst source track` does for `tar`/`remote` sources (it
downloads the URL and writes back the sha256 — see `/apache/buildstream`
`DownloadableFileSource.track`), so either works:

```
# Option A: compute the digest of the artefact at the BUMPED url and hand-edit ref:
curl -sL <url> | sha256sum

# Option B: on a checkout of the renovate branch (rewrites the file in
# BuildStream's canonical YAML style — expect whole-file reflow):
BST_LOCAL=1 just bst source track <element>
```

Then `just validate` and, to prove the fetch end-to-end, `just bst source fetch <element>`.

Two shortcuts worth knowing:

- The CI failure log prints the **actual** digest (`has sha256sum '<actual>'`); it is
  trustworthy, but recompute it yourself anyway — that check is the supply-chain
  guarantee, not a formality.
- When several Renovate PRs are stuck on the same drift, landing one PR on main that
  applies the bumps **with** correct refs makes the Renovate PRs obsolete; Renovate
  autocloses them on its next run. That is usually less churn than force-pushing fixes
  onto each bot branch.

## Adding a new upstream package

Put the version in a **variable**, annotate it, and build the URL from it. Never hardcode a
version into a `url:` — a literal URL is invisible to Renovate, and that is exactly how
`qemu` silently fell three major versions behind.

```yaml
variables:
  # renovate: datasource=github-releases depName=<org>/<repo>
  <tool>_version: 1.2.3
sources:
  - kind: tar
    url: https://example.org/<tool>-%{<tool>_version}.tar.gz
    ref: <sha256>
```

The annotation is read by the single `customManagers` regex in `renovate.json`, which
matches any `# renovate:` comment on the line **before** the pinned value. It works in
`.bst` files and in the `Justfile`.

Supported keys: `datasource` (required), `depName` (required), `versioning`, `extractVersion`.

### Choosing a datasource

| Upstream publishes | Use |
|---|---|
| GitHub releases | `datasource=github-releases depName=org/repo` |
| GitHub tags only | `datasource=github-tags depName=org/repo` |
| GitLab tags | `datasource=gitlab-tags depName=group/repo` |
| PyPI | `datasource=pypi depName=package` |

When the tag is not a bare version, strip it with `extractVersion`:

```yaml
# renovate: datasource=github-tags depName=nginx/nginx extractVersion=^release-(?<version>.+)$
nginx_version: 1.29.8
```

### Getting the initial ref

```
just bst source track <element>          # writes the ref for you
```

Beware: `bst source track` rewrites the file in BuildStream's canonical YAML style, which
reflows indentation across the whole element. For a hand-edit, compute the hash directly
instead — `ref:` for `tar`/`remote` sources is a plain sha256 of the downloaded file:

```
curl -sL <url> | sha256sum
```

## Verifying your annotation actually matches

An annotation that the regex does not match is worse than none — it looks tracked and never
fires. Check it:

```
python3 - <<'PY'
import re, json, glob
cfg = json.load(open('renovate.json'))
rx = re.compile(cfg['customManagers'][0]['matchStrings'][0].replace('(?<', '(?P<'))
files = sorted(glob.glob('elements/**/*.bst', recursive=True)) + ['Justfile']
n = 0
for f in files:
    for m in rx.finditer(open(f).read()):
        n += 1
        print(f, m.groupdict()['depName'], m.groupdict()['currentValue'])
print('matched', n, 'of', sum(open(f).read().count('# renovate:') for f in files))
PY
```

The matched count **must** equal the annotation count. Then validate the config itself:

```
npx --yes --package renovate -- renovate-config-validator renovate.json
```

## Why these are never automerged

`renovate.json` sets `automerge: false` for the `custom.regex` manager. A version bump here
changes the contents of a shipped image: the ref must be refreshed, the build must succeed,
and `just verify` (size ceiling + gates + smoke test) must pass. GitHub Actions bumps are
automerged; upstream software is not.

## Known gap

`bst2_image` in the `Justfile` is pinned to a commit-SHA tag
(`.../bst2:64eb0b49...`). Renovate cannot order SHA tags, so it is **not** tracked. To
automate it, the image must first be pinned by digest (`:tag@sha256:...`), after which the
`docker` datasource can track the digest.

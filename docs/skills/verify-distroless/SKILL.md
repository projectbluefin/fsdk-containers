---
name: verify-distroless
version: "1.1"
last_updated: "2026-09-18"
id: verify-distroless
one_line_purpose: Run and extend the per-image verify contract that gates every merge.
entry_point: docs/skills/verify-distroless/SKILL.md
category: test-authoring
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [verification, testing, distroless, gates]
description: "Run and understand the distroless + slim verification gates. Use when validating an image before merge, debugging a failed gate, or adding a new gate."
metadata:
  type: procedure
---

# Verify Distroless

`just verify` is the merge contract. It builds nothing — it inspects the loaded
`ghcr.io/projectbluefin/<name>:build` image. All gates must pass.

## When to Use

- Validating an image locally before opening or merging a PR.
- Debugging a failed gate: a shell binary found in the rootfs, a missing CA bundle
  or `zoneinfo/UTC`, or reappeared slim bloat.
- Debugging a red `pr-build-oci (<image>, <arch>)` job — that job runs `just build`
  then `just verify`, so a gate failure surfaces there.
- Adding a gate after cutting something new in the SLIM recipe.
- Adding a new image or runtime component, or moving to a new FSDK series, and
  extending coverage to match.

Not for deciding *what* to cut — that is
[`../slim-an-image/SKILL.md`](../slim-an-image/SKILL.md).

## Local quality gates on top of upstream

`fsdk-containers` adds distroless-specific checks via `just verify`. For
distroless images (everything except the shell-enabled `lab-runner`):

1. **No shell binary in rootfs.** Exports the container filesystem and greps for
   `(ba)?sh` in the path list. The bash binary lives in FSDK's `runtime` domain
   (NOT `shells`), so it is removed by explicit `rm` in the SLIM recipe, not by a
   compose exclude.
2. **CA certificates present** — `etc/(ssl|pki)/.*(ca-bundle|cert)` in the rootfs.
3. **tzdata present** — `usr/share/zoneinfo/UTC`. A kept crash-preventer.
4. **Slim bloat removed** — fails if sanitizer/Fortran runtimes,
   locale archives/charmaps, leaked locale/build tools, or extra PCRE2 widths
   reappear. Regression guard for the shared SLIM recipe. (terminfo is NOT
   bloat: it has been deliberately kept in every image since #101 — see
   [`references/terminfo-seam.md`](references/terminfo-seam.md).)

`lab-runner` is an explicit shell-enabled exception: it asserts that `bash` is
present, that `argo`, `just`, `kubectl`, `shellcheck`, `hadolint`, and
`actionlint` are on disk and executable, and that the full terminfo database
is present — the direct-color pairs (`xterm-direct`/`tmux-direct`,
`xterm-256color`/`screen-256color`), a >=1000-entry completeness floor, and
`xterm-ghostty` (see [`references/terminfo-seam.md`](references/terminfo-seam.md)).

## Run it

```
just verify
```

Rootless podman works; the recipe auto-detects and only uses `sudo` if `podman
info` fails.

## Debugging a failure

Export the rootfs and inspect directly. Distroless images have no CMD or
ENTRYPOINT in their OCI config — `podman create` requires a placeholder command
to succeed (it does not validate whether the command exists in the image):

```
cid=$(podman create ghcr.io/projectbluefin/<name>:build /nonexistent)
podman export "$cid" | tar -tf - | grep -E '<thing you expect/don.t expect>'
podman rm "$cid"
```

A functional smoke test (loader + libc) on a distroless image — run a real binary,
not a shell:

```
podman run --rm ghcr.io/projectbluefin/<name>:build /usr/bin/env
```

## Red Flags

- **Relying on `compose exclude: shells` to make an image distroless.** The `shells`
  split-rule domain covers only `/usr/share/fish` and `/usr/share/zsh` data dirs; the
  bash binary (`/usr/bin/bash`, `/usr/bin/sh -> bash`) lives in the FSDK `runtime`
  domain. The SLIM recipe `rm`s it explicitly (`include/slim.yml`); see hard rule 4 in
  [`../../../AGENTS.md`](../../../AGENTS.md) and the NOTE in
  `elements/nginx/nginx-runtime.bst`.
- **Deleting terminfo as "bloat".** It is deliberately kept in every `base-stack`
  image since #101 and asserted by the `lab-runner` gate. The slim gate explicitly
  does not treat it as bloat.
- **Smoke-testing a distroless image through a shell** (`podman run … /bin/sh -c …`).
  There is no shell. Execute a real binary; execution is the only proof that the
  dynamic dependencies survived `compose`.
- **Cutting something in the SLIM recipe without adding a matching negative `grep`
  assertion** to the verify gates — the bloat creeps back silently on the next FSDK
  point release.
- **Smoke-testing on one architecture only.** A library that moved domains can pass
  `bst show` and still fail at runtime on the other architecture.

## Verification

`just verify` is itself the verification command — it is the merge contract, not a
convenience wrapper:

```
just validate                                  # graph resolves, junction + patches valid
BUILD_IMAGE_NAME=<image> just build
BUILD_IMAGE_NAME=<image> just verify           # content gates + smoke test
just sbom <image>                              # SPDX inventory for the same element
```

CI runs exactly these two lines per image/arch inside the `pr-build-oci` job
(`.github/workflows/build.yml`, the "Build and verify" step), so **a green
`pr-build-oci (<image>, <arch>)` is the verify contract for that image on that
architecture.** Nothing else proves it — `just validate` only resolves the graph.

To re-derive the gate set rather than trusting this doc:

```
python3 scripts/verify_contract.py <image> --env   # the image's gates
grep -n 'FORBIDDEN' -A 20 scripts/verify_contract.py
grep -n 'just build\|just verify' .github/workflows/build.yml
grep -n 'bash' include/slim.yml                    # the explicit shell removal
```

## Reference material

| File | Contents |
|---|---|
| [`references/inherited-upstream-coverage.md`](references/inherited-upstream-coverage.md) | What upstream Freedesktop-SDK CI already proves about every artifact we pull, plus local graph validation and the post-build supply-chain attestations. |
| [`references/terminfo-seam.md`](references/terminfo-seam.md) | Why terminfo is kept in every `base-stack` image (#101) and how the vendored `xterm-ghostty` entry works (#105). |
| [`references/extending-coverage.md`](references/extending-coverage.md) | Extending the contract: adding a new runtime component or image, moving to a new FSDK series, and adding a gate. |

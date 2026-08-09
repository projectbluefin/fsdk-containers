---
name: bump-fsdk-version
version: "1.0"
last_updated: 2026-08-08
id: bump-fsdk-version
one_line_purpose: Move the project to a new freedesktop-sdk release and refresh derived tags.
entry_point: docs/skills/bump-fsdk-version.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [fsdk, versioning, junction, tags]
description: "Move fsdk-containers to a new freedesktop-sdk release and refresh the derived tags. Use when tracking the FSDK lifecycle or pinning a new FSDK point release."
metadata:
  type: runbook
---

# Bump the FSDK Version

Use when moving to a new FSDK release, or refreshing the pinned ref.

## The version model

There is no application version for these images — the version axis IS the FSDK
release. Tags are derived from the pinned junction ref in
`elements/freedesktop-sdk.bst` (the `ref:` line, e.g.
`freedesktop-sdk-25.08.13-...`):

- `:25.08` or `:26.08` — FSDK minor line (moves within the line; the most
  rolling tag published — there is deliberately no `:latest`)
- `:25.08.14` — FSDK point release, treated **immutable**
- `:26.08beta.1` / `:26.08rc.1` — pre-release/beta/RC release tag (published whenever tracking upstream dev/beta branches)

`just tags` parses these from the ref. Provenance labels
`io.projectbluefin.fsdk.version` / `io.projectbluefin.fsdk.ref` are applied at
export so every image self-declares its base. The
`org.opencontainers.image.ref.name` index annotation in `elements/oci/*.bst`
substitutes `%{fsdk-version}` (from the gitignored `include/fsdk-version.yml`
that `just bst` regenerates), so a bump needs no edit there. We aim to track
every upstream development and beta branch, ensuring images are continuously
built and published for early testing.

## Procedure

1. Find the target ref/tag upstream:
   <https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/releases>
   (or the `freedesktop-sdk-YY.MM` branch tip for a minor line).

2. Update the `ref:` in `elements/freedesktop-sdk.bst` to the new tag/commit.

3. Re-check patches still apply — FSDK ships local patches under
   `patches/freedesktop-sdk/`. If a release changed the patched files, refresh or
   drop them. `just validate` surfaces patch failures.

4. Rebuild and verify:

   ```
   just validate
   just tags        # confirm derived tags look right
   just build
   just verify
   ```

5. Follow the FSDK **lifecycle**: track the active minor line; when FSDK EOLs a
   line, move consumers to the next supported minor. Don't pin to an EOL line.

## Verification

Before merging a bump:

- [ ] `just validate` passes (element graph resolves with new ref)
- [ ] `just tags` output matches the expected `YY.MM / YY.MM.PP` pair and
      contains no `latest`
- [ ] Both CAS-config patches (`0001`, `0002`) applied cleanly (no patch failure in `just validate`)
- [ ] `just build && just verify` — size ceiling, all gates, and the smoke test pass
- [ ] `io.projectbluefin.fsdk.version` label on the built image matches the new FSDK version

- Bumping across a minor line (e.g. 25.08 → 26.08) may rename/relocate components or restructure runtime stacks:
  - **FSDK 26.08 "Choose Your Own Userland" (verified on `26.08beta.2`).**
    `public-stacks/runtime-minimal.bst` no longer contains bash or coreutils —
    they now live only in `public-stacks/runtime-gnu.bst`. Additionally,
    `integration/ldconfig.bst` changed from `depends:` to `build-depends:` on
    `runtime-gnu` between beta.1 and beta.2, closing a long-standing leak that
    had been pulling a full GNU userland into the *runtime* closure of every
    consumer. That leak is why our "distroless" images shipped ~184 binaries
    that `include/slim.yml` then deleted.
  - **The symptom is `Staged artifacts do not provide command 'sh'`.** Anything
    that runs a shell script now needs the shell declared. Two classes break:
    - Stacks whose components carry shell integration-commands
      (`base-stack.bst`, `static-stack.bst` — `update-ca-trust` and `ldconfig`
      are shell scripts) need `public-stacks/runtime-gnu.bst` in `depends:`.
    - Every `kind: script` element in `elements/oci/` runs the SLIM recipe,
      which is a shell script, and needs `bootstrap/bash.bst` +
      `bootstrap/coreutils.bst` in `build-depends:`. Before 26.08 only
      `oci/qemu-img.bst` declared these; the rest inherited a shell by accident.
  - **`components/systemd-base.bst` was removed in 26.08.** The
    `gnome-build-meta` systemd overrides in `elements/freedesktop-sdk.bst` must
    be dropped: gnome-build-meta (both `gnome-50` and `master`) is still pinned
    to FSDK 25.08 and still references `systemd-base.bst`, so keeping the
    overrides fails to load the junction entirely.
  - Re-confirm `components/*` and `public-stacks/*` names against the staged junction before assuming a dep still exists.
- **Tag refs must be the dereferenced commit, not the tag object.** FSDK tags are
  annotated, so `git ls-remote --tags` returns the tag object SHA. Use the
  `refs/tags/<tag>^{}` line, or `bst source track`, or the junction will not
  resolve.
- A point-release tag is immutable: once `:25.08.13` is published, never republish
  different bits under it.
- **Only the systemd-* overrides and two CAS-config patches remain.** When Dakota
  syncs a new FSDK pin, check whether `patches/freedesktop-sdk/0001` and `0002`
  (CAS limits + GNOME CAS servers) still apply cleanly. All other dakota patches
  (openssh, lvm2, pipewire, cross-compilers, frei0r, kernel-v3) were stripped
  because this repo never builds those components.
- **Junction overrides are only meaningful for components your local elements
  reference directly.** The 25 GNOME sdk/* overrides (cairo, gtk3, pango, glib,
  gdk-pixbuf…) were dead weight — none of our `base-stack`, `brew-deps` etc. ever
  reference those components. If you copy a junction from dakota in the future,
  strip every override whose component is not in your local dep graph.

## Automated FSDK Release Tracking

FSDK releases (point releases and beta/pre-releases) are tracked automatically via the `.github/workflows/auto-update-fsdk.yml` GHA workflow.
- **Trigger:** Daily cron schedule at `03:00 UTC` and manual `workflow_dispatch`.
- **Mechanism:** Runs `just bst source track freedesktop-sdk.bst` to check for newer refs on the tracking line. If the junction ref changes, the workflow validates the element graph, opens an automated PR on a version-specific branch (`auto/update-fsdk-<version>`), and dispatches a verification build via `repository_dispatch`.
- **Build Loop:** The dispatched build workflow checks out the PR branch, rebuilds, verifies, and publishes the new release tags and manifests. Rolling and minor-line manifests are only assembled when both `x86_64` and `aarch64` builds succeed, preventing a single failed architecture from overwriting multi-arch tags.

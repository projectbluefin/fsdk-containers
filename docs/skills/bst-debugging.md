---
name: bst-debugging
version: "1.0"
last_updated: 2026-08-09
id: bst-debugging
one_line_purpose: Classify and fix BuildStream element build failures before escalating to a full image build.
entry_point: docs/skills/bst-debugging.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [buildstream, debugging, builds, cache, remote-execution]
description: "Debug BuildStream build failures. Use when `just build` fails, `bst show` errors, source fetch breaks, or an element builds but its content is missing from the final image."
metadata:
  type: procedure
  context7-sources:
    - /apache/buildstream
---

# Debugging Build Failures

## Overview

**Element-level debugging.** Use it when the element graph or a build step is the
problem — not when GitHub Actions plumbing is the problem.

Adapted from `projectbluefin/dakota`'s `docs/skills/debugging.md`. The classification
model and the cheapest-command-first discipline are shared; the element paths and the
remote-execution topology are this repo's.

## When to Use

- `just build` / `just bst build <element>` fails
- `just validate` or `just bst show` errors
- source fetch or ref tracking fails
- an element builds fine but the content is missing from the image

## When NOT to Use

- CI trigger, token, or workflow problems → [ci-tooling](ci-tooling/SKILL.md)
- Writing a new element from scratch → [add-new-image.md](add-new-image.md) or
  [buildstream.md](buildstream.md)
- Junction refs / patch queue / cache-key questions → [bst-junctions.md](bst-junctions.md)
- The grid itself is unreachable → [remote-execution.md](remote-execution.md)
- The image builds but fails a gate → [verify-distroless](verify-distroless/SKILL.md)

## Core Process

1. **Classify the failure first** — graph/YAML, fetch/ref, compile, install/staging,
   or image composition. The class determines the tool.
2. **Use the cheapest inspection command first.** `bst show` before `bst build`;
   `artifact log` before guessing; `artifact list-contents` before blaming compose.
3. **Reproduce in the sandbox** only once you know which phase failed.
4. **Escalate to a full image build last.**

## Quick Reference

| Action | Command |
|---|---|
| Resolve the graph | `just validate` |
| Inspect one element | `just bst show oci/<name>.bst` |
| Build one element | `just bst build <name>/<name>-runtime.bst` |
| Enter the build sandbox | `just bst shell --build <element>` |
| Read the build log | `just bst artifact log <element>` |
| List built files | `just bst artifact list-contents <element>` |
| Delete a cached failure | `just bst artifact delete <element>` |
| Force local execution | `BST_LOCAL=1 just build` |
| Full build after the fix | `just build` then `just verify` |

## Failure Classes

### 1) Graph / YAML errors

**Symptom:** `Error loading project` — or any failure that appears *before* a `[build]`
line. The element never started building.

This is a YAML or option error, not a build failure. Run `just bst show <element>` (no
build) to pinpoint it. Common causes: bad indentation, hyphenated option names (only
alphanumerics and underscores are legal), wrong option type, a source URL using a
missing alias, malformed element structure.

**Do not open a sandbox until `bst show` exits cleanly.**

### 2) Source fetch failures

Typical causes: a stale `ref:`, a moved upstream URL, or a tarball layout mismatch.

- `just bst source track <element>` to re-resolve a ref
- add or fix the alias in `include/aliases.yml` (URLs do not expand `%{variables}`)
- `base-dir: ""` for tarballs with no wrapping directory

### 3) Compile failures

Typical causes: a missing build dependency, upstream path assumptions (`/usr/sbin`,
`/lib` — FSDK is merged-usr), or pkg-config visibility.

Note that a build dep can be present locally and missing remotely. Elements have needed
explicit `bash`/`coreutils` build-deps to work in the FSDK sandbox — see the recent
`qemu-img` and `cloud-init` fixes in this repo's history.

### 4) Install / staging failures

Typical causes:

- **Missing `strip-binaries: ""` for non-ELF payloads.** The signature is
  `freedesktop-sdk-stripper` exiting `127` while the `install-commands` are plainly
  correct. BuildStream's default strip step is choking on a file that is not an ELF
  binary — plain text, shell scripts, fonts, JSON, prebuilt archives. Set
  `variables: { strip-binaries: "" }` on that element.
- Forgot `mkdir -p` before an install or symlink target
- An overlap conflict → see the overlap section of [buildstream.md](buildstream.md)
- Files landing outside `/usr`

### 5) Image composition failures

The element built, but its content is not in the image.

Typical causes: the element is not wired into the image's `-stack.bst`; the layer is
`kind: stack` where it needed to be `kind: compose` (a stack produces **no** filesystem
output); the SLIM recipe or a per-runtime prune deleted it; or a downstream compose
cache did not invalidate.

`just bst artifact list-contents <element>` settles "did it build the file?" before you
argue about compose.

## Remote-execution failures

Local and agent builds run on the ghost cluster's BuildBarn grid by default. That adds
failure modes that do not exist locally.

- **Distinguish an input-root staging error from a compile error.** A message like
  `Failed to obtain input directory ".": Object not found` is a grid/staging failure,
  not a broken compiler. Diagnose the grid; do not "fix" the element.
- **`/dev/stdin` redirection fails on the grid but passes locally.** Bubblewrap mounts
  `/proc`, a bare chroot runner does not. Use `install -Dm644 /dev/null <target>` then
  `cat > <target> <<'EOF'`. See [buildstream.md](buildstream.md).
- **Go builds need explicit `GOROOT: "%{libdir}/go"`** or remote actions fail with
  `go: cannot find GOROOT directory` even though `go` is present.
- **`BST_LOCAL=1` is a diagnostic, not an operating model.** Use it to isolate whether a
  failure is the element or the grid, then restore remote execution. `just bst` fails
  closed when the cluster is unreachable, deliberately — do not add a silent local
  fallback. See [remote-execution.md](remote-execution.md).

## Cache traps

- **A failed build is cached as a failed artifact.** `bst show` reports the element as
  `failed` and retries exit immediately without rebuilding. Clear it with
  `just bst artifact delete <element>` before you try again. Agents routinely misread
  this as "my fix did nothing".
- **A corrupt remote blob does not self-heal.** BuildStream does not fall back to
  rebuilding when a pull fails midway; the build stays broken. Bust the cache key to
  force a clean rebuild (a no-op change to the element is enough).
- **Weak-key caching can hide a new dependency.** Changing a `kind: stack` dependency
  does not always invalidate downstream `compose` output in non-strict mode. If a
  package is in the graph but missing from the image, suspect cache behaviour before
  rewriting the element.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "The build failed, so I need the sandbox now." | Not if `bst show` is already telling you it is a YAML error. |
| "CI failed, so this is a CI problem." | Most CI failures are element failures surfacing remotely. Classify first. |
| "It's missing from the image, so the build failed." | It may have built cleanly and never been wired into the stack or compose. |
| "My fix did nothing — same error." | You are hitting a cached failed artifact. Delete it. |
| "Remote execution is flaky, I'll just build locally." | `BST_LOCAL=1` is a diagnostic. A permanent local fallback violates the build model. |
| "I'll skip to a full image build." | The slowest feedback loop available. |

## Red Flags

- opening the sandbox before reading the log
- debugging compile flags while the graph does not parse
- rerunning full image builds to chase a single-element syntax error
- adding `BST_LOCAL=1` to a workflow or committing it as a default
- extending a timeout instead of diagnosing why an action is slow

## Verification

- [ ] The failure class was identified before deep debugging
- [ ] `just validate` is clean before sandbox work began
- [ ] Logs or artifact contents were inspected before guessing
- [ ] Single-element debugging was exhausted before a full rebuild
- [ ] Any cached failed artifact was deleted before re-testing
- [ ] The fix explains **why** it failed, not just how it was silenced
- [ ] `just verify` passes for every image touched

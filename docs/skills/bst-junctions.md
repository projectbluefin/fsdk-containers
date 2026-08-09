---
name: bst-junctions
version: "1.0"
last_updated: 2026-08-09
id: bst-junctions
one_line_purpose: Keep junction refs, patch queues, and options cache-key aligned so builds pull instead of compile.
entry_point: docs/skills/bst-junctions.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [buildstream, junctions, patches, cache-keys, freedesktop-sdk]
description: "How the freedesktop-sdk and gnome-build-meta junction refs, patch queues, and project options determine cache-key alignment. Use when bumping a junction, touching patches/, or diagnosing cache misses."
metadata:
  type: reference
  context7-sources:
    - /apache/buildstream
---

# Junctions, Patch Queues, and Cache Keys

## Overview

This repo builds almost nothing of its own — it composes FSDK `components/*` through a
junction. So **the junction's cache key decides whether a build is a download or a
compile.** Getting it wrong does not produce a wrong image; it produces a build that
takes hours instead of minutes, silently.

Adapted from `projectbluefin/dakota`'s `docs/skills/bst-overrides.md` and
`docs/skills/patch-junctions.md`. **Those two dakota docs contradict each other** —
see [Correcting the inherited rule](#correcting-the-inherited-rule) — and this file
carries the version that is actually true.

## When to Use

- Bumping `elements/freedesktop-sdk.bst` or `elements/gnome-build-meta.bst`
- Adding, removing, or reordering a patch under `patches/`
- Diagnosing "why is BuildStream compiling glibc instead of pulling it?"
- Evaluating whether a local override is justified

## When NOT to Use

- Moving to a new FSDK release as a versioning/retag exercise →
  [bump-fsdk-version.md](bump-fsdk-version.md)
- Generic element syntax → [buildstream.md](buildstream.md)
- A build failure that is not cache-related → [bst-debugging.md](bst-debugging.md)

## What busts a cache key

Grounded in BuildStream's cache-key architecture (`/apache/buildstream`,
`arch_cachekeys`). An element's strong key covers its own config, variables and
environment, its source refs, and **all of its build-dependency keys, recursively**.

Consequences, widest blast radius first:

| Change | Invalidates |
|---|---|
| Junction `ref:` bump | every element that junction provides |
| Junction `patch_queue` change | same — the queue is part of the junction's source hash |
| `project.conf` options or variables | project-wide |
| A leaf element ref bump | that element and its reverse deps only |
| Workflow / Justfile / docs changes | nothing |

**Merge ordering rule for queued update PRs:** leaf bumps first, junction bumps last,
one at a time, each verified green before the next.

## Correcting the inherited rule

Dakota's `patch-junctions.md` states, in a fenced block, `NO LOCAL JUNCTION PATCH
QUEUES`, and claims all junction patches were removed. **That rule as written is
false, and copying it here would be actively harmful.** Evidence:

- `dakota/patches/freedesktop-sdk/` currently holds **7** patches.
- Dakota's own `bst-overrides.md` states the opposite and correct nuance: the queue
  "must stay byte-identical to GBM's `patches/freedesktop-sdk/` directory at the
  pinned GBM commit", enforced in CI by `just patch-drift-check`.
- This repo carries a `patch_queue` on its FSDK junction too, and
  `elements/gnome-build-meta.bst` documents why in an inline comment:
  *"This along with the patches is required and has to match what gnome-build-meta
  is using."*

**The real principle:** a junction's patch queue is part of its cache key, so the
queue selects *which upstream artifact cache you can reuse*.

- Patches that **diverge** from what your upstream parent pins are cache-destroying.
  That is the thing to prohibit.
- Patches that **replicate** the parent's queue byte-for-byte are cache-*aligning*,
  and are mandatory rather than forbidden.

The enforceable rule is **drift control against the parent's queue at the pinned
ref** — not "never patch a junction". Deleting this repo's `0001`/`0002` patches
because a doc said "no patch queues" would move it *further* from GBM, not closer.

## Measured: this repo does not currently reuse GBM's cache

`project.conf` lists `https://gbm.gnome.org:11003` as an artifact and source cache,
which implies the intent is to reuse GNOME's FSDK artifacts. **Measured 2026-08-09,
that reuse cannot be happening**, for three independent reasons:

| | This repo | GBM at our pinned GBM ref (`cc8cb59`) |
|---|---|---|
| FSDK `ref:` | `freedesktop-sdk-26.08beta.2` (on `main`) | `freedesktop-sdk-25.08.13` |
| `patches/freedesktop-sdk/` | 2 patches (`0001`, `0002`) | 7 patches (`0001`–`0007`) |
| `x86_64_v3` option | not defined (banned by AGENTS.md) | set via `(?)` in the junction |

Any **one** of these makes our FSDK junction key differ from GBM's; all three do.
So every FSDK-derived element must come from `cache.projectbluefin.io` or be compiled
locally — `gbm.gnome.org` contributes nothing at the current pin.

**This is not automatically a bug.** Two of the three divergences are deliberate: the
`x86_64_v3` ban is a hard rule, and the FSDK line is a live decision (#125/#126). But
it should be a *chosen* trade-off, not an accident, and the `x86_64_v3` divergence
alone may be sufficient to make GBM reuse permanently impossible — in which case the
`gbm.gnome.org` cache entry is decoration and the 2-patch queue is cargo cult.

**Unverified / open:** whether pinning FSDK to exactly GBM's ref *and* matching all 7
patches would actually restore reuse, given the `x86_64_v3` option difference. Nobody
has measured a before/after cache-hit rate here. Do not assert a number until someone
does. For scale, dakota measured that removing a single divergent junction patch
restored **1053 of 1090** elements from cache (96%) — so the effect size is large
enough to be worth measuring properly.

## Upstream-first

Local overrides are maintenance debt. The order of preference is always:

1. **Check whether upstream already fixed it** → bump the junction ref.
2. **Fix it upstream** → submit the patch, reference the MR.
3. **Override locally, last resort** → only with a documented exit condition.

| Question | If yes → |
|---|---|
| Is the fix in upstream's latest ref? | Bump the ref instead |
| Will upstream accept it this cycle? | Submit upstream; carry a temporary patch with `Upstream-Status: Submitted <URL>` |
| Is this genuinely repo-specific? | Local override is justified — document why |
| Is it a security backport? | Justified — link the CVE and the upstream fix |

Every patch and override needs an exit condition, written down:

```
Upstream-Status: Submitted https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/merge_requests/NNN
Exit condition: Drop after FSDK ships <release>
Exit condition: Permanent — repo-specific, not upstreamable
```

Without one it becomes permanent debt with no path to removal.

## No local toolchain workarounds

If a dependency fails to build under the baseline toolchain, **do not** compile a local
GCC, ship a bootstrap toolchain, or add compiler-specific hacks. Align to an upstream
ref that works instead. In dakota this was learned expensively: local compiler
workarounds on the junction invalidated the whole imported graph and forced the runners
to rebuild glibc, systemd and the compiler itself, producing OOMs and multi-hour builds.

## Patch queue mechanics

Patches apply in **alphabetical filename order**. Numbering gaps are intentional —
they leave room to insert without renaming. To insert between `0004` and `0005`, name
it `0004b-...`; do not renumber the tail to make the sequence look tidy.

## Void-override pattern

To remove a junction-provided component entirely rather than patch it, override it to
an empty `kind: stack` element — the same pattern GBM uses for `void/zenity.bst`:

```yaml
# elements/freedesktop-sdk.bst
config:
  overrides:
    components/<unwanted>.bst: <local-void-element>.bst
```

Cache impact check before committing: if everything downstream of the element is
already uncached, the void override is cache-neutral. Compare `just bst show` state
counts before and after.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Patch queues on junctions are banned." | Only *divergent* ones. Replicating the parent's queue is what makes cache reuse work. |
| "I'll just override it locally for now." | Debt, unless it has a written exit condition. |
| "Editing the junction file directly is faster." | Faster at creating debt. |
| "We'll remember to drop the patch later." | You won't. Write the exit condition. |
| "The build is slow, so raise the timeout." | Slow usually means a busted cache key. Find what diverged. |
| "gbm.gnome.org is in project.conf, so we're getting its artifacts." | Not unless the junction key matches. Measure it. |

## Red Flags

- a junction patch with no `Upstream-Status` and no exit condition
- a patch queue that drifts from the parent project's without a stated reason
- an override surviving multiple junction bumps without re-evaluation
- direct edits to junction files as a convenience move
- any reintroduction of `x86_64_v3`, or a local GCC
- raising a timeout in response to a slow build

## Verification

- [ ] Upstream was checked before the override or patch was created
- [ ] The narrowest mechanism that works was used
- [ ] An exit condition is written down
- [ ] The patch queue's relationship to GBM's queue is deliberate and stated
- [ ] Cache impact was considered, and measured if claimed
- [ ] `just validate` resolves and `just verify` passes after the bump

---
name: bst-junctions
version: "1.1"
last_updated: "2026-09-18"
id: bst-junctions
one_line_purpose: Keep junction refs, patch queues, and options cache-key aligned so builds pull instead of compile.
entry_point: docs/skills/bst-junctions/SKILL.md
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
see [Correcting the inherited rule](references/patch-queue-policy.md#correcting-the-inherited-rule) —
and this skill carries the version that is actually true.

## When to Use

- Bumping `elements/freedesktop-sdk.bst` or `elements/gnome-build-meta.bst`
- Adding, removing, or reordering a patch under `patches/`
- Diagnosing "why is BuildStream compiling glibc instead of pulling it?"
- Evaluating whether a local override is justified

## When NOT to Use

- Moving to a new FSDK release as a versioning/retag exercise →
  [bump-fsdk-version.md](../bump-fsdk-version.md)
- Generic element syntax → [buildstream](../buildstream/SKILL.md)
- A build failure that is not cache-related → [bst-debugging.md](../bst-debugging.md)

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

## Reference files

| File | What's in it |
|---|---|
| [patch-queue-policy.md](references/patch-queue-policy.md) | Why "no junction patch queues" is the wrong rule, patch application order, and the void-override pattern for deleting a junction-provided component |
| [cache-reuse-measurements.md](references/cache-reuse-measurements.md) | Dated measurements of why `gbm.gnome.org` reuse is not happening, the open lead on this repo's GBM patch queue, and the commands to re-derive both |
| [upstream-first.md](references/upstream-first.md) | The override escalation ladder, mandatory exit conditions, and the ban on local toolchain workarounds |

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
- quoting a junction ref or patch count from this skill instead of re-deriving it
  (see [cache-reuse-measurements.md](references/cache-reuse-measurements.md))

## Verification

- [ ] Upstream was checked before the override or patch was created
- [ ] The narrowest mechanism that works was used
- [ ] An exit condition is written down
- [ ] The patch queue's relationship to GBM's queue is deliberate and stated
- [ ] Cache impact was considered, and measured if claimed
- [ ] `just validate` resolves and `just verify` passes after the bump

Current junction pins and patch counts are derived, never quoted from memory:

```bash
grep -n 'ref:' elements/freedesktop-sdk.bst
grep -n 'ref:' elements/gnome-build-meta.bst
ls patches/freedesktop-sdk/ patches/gnome-build-meta/
grep -rn 'x86_64_v3' project.conf elements/   # prose reminders only — never an
                                              # option definition (AGENTS.md ban)
```

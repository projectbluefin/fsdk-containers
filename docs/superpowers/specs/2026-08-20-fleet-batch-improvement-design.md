# Fleet Batch Improvement — Issue Triage + Parallel Execution Design

Date: 2026-08-20
Status: approved (user: "GO!", scope=full-batch, labels authorized)
Session driver: GitHub Copilot CLI, fleet mode (parallel subagents)

## Intent

Review and triage all open issues in `projectbluefin/fsdk-containers`, then
batch-improve the project by fanning work out to a fleet of parallel subagents,
each with a bounded, disjoint objective.

## Triage routing (applied)

Per the canonical seven-label contract (common/docs/skills/label-workflow.md):

| Issue | Label applied | Rationale |
|---|---|---|
| #177 auto-update-fsdk push auth unmasked | `3-clanker-queue` | One-step automatable fix |
| #160 Build images flaky on main | `3-clanker-queue` | Agent diagnosis of failure signature |
| #110 podman-vm guest no boot on 26.08 | `3-clanker-queue` | Bounded diagnosis; blocks #78 |
| #146 Wave 0 feasibility spikes | `3-clanker-queue` | 8 unblocked inert stack elements |
| #74 lab-runner runtime contract | `2-discussing` | Contract decision — human |
| #79 contributor identity in VM guest | `2-discussing` | Ownership/contract decision — human |
| #89 lab-runner linters | kept `3-clanker-queue` | Queued; blocked on #74's decision |
| #126, #128, #130, #123, #113, #124 | kept wayfinder labels | HITL grilling / AFK research / map |
| #3 Dependency Dashboard | `hold` (removed `1-triage`) | Automation-owned, no action |

## Fleet batch 1 (all parallel, disjoint state)

| Agent | Objective | Output |
|---|---|---|
| fix-177 | extraheader + `base64 -w0` + `::add-mask::` in auto-update-fsdk.yml | PR closing #177 |
| diag-160 | Common failure signature across runs 31757712369 / 31596423400 / 31570830518 | Comment on #160 |
| diag-110 | Root-cause hypothesis for QEMU boot-to-ready failure | Comment on #110 |
| spike-curl / go / nginx / valkey / postgres / mariadb / node / falco | One inert stack element each; must resolve AND build on the ghost BuildBarn grid; mechanism/deps/resolution/version recorded in element comments | 8 PRs, "Part of #146" |
| main session | Decision briefs for #74, #79, #126, #128, #130 | Comments on each |

Spike agents each work in a dedicated git worktree (`../fsdk-wt-<target>`,
branch `spike-146-<target>`) so parallel git state never collides.

Out of scope for batch 1: `volcano` and `kubestellar-hive` (gated on #144,
go_module enablement), any change to `targets.json`, any OCI element — spikes
stay inert by design.

## Batch 2 (after batch 1 lands)

1. Implement the fix the #160 diagnosis identifies (retry or dependency fix).
2. Implement the fix the #110 diagnosis identifies; unblock VM guest publication (#78).
3. Record mechanism corrections from the 8 spikes into #146's table and #113's Wave 4 batches.
4. Once the human answers #74/#79 decision briefs, route resulting work to `3-clanker-queue`.

## Guards

- `just verify` green before any image-affecting PR merges.
- Compose from `components/*`, never `platform.bst`; no `x86_64_v3`.
- Upstream-maintained distroless images are consumed, not rebuilt (falco spike explicitly checks this).
- Agents never push to main, never self-merge, never touch `ublue-os/*`.
- Every PR carries `Closes #NNN` or `Part of #NNN`.

## Success criteria

- #177 closed by PR.
- #160 and #110 each carry an evidence-backed diagnosis comment.
- 8 spike PRs open, each with a grid-built stack element and the four Wave-0 answers.
- 5 decision briefs posted, each answerable in under 5 minutes.
- All routing labels consistent with the seven-label contract.

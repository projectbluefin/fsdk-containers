# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those
roles to the actual label strings used in this repo's issue tracker.

This repo does **not** use the canonical label names. It inherits the numbered
lifecycle vocabulary from
[`projectbluefin/common`](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).
Apply the right-hand column — never create the left-hand names as new labels.

| Canonical role    | Label in our tracker | Meaning                                        |
| ----------------- | -------------------- | ---------------------------------------------- |
| `needs-triage`    | `1-triage`           | New work awaiting human triage                 |
| `needs-info`      | `2-discussing`       | Requires discussion or a clarified design      |
| `ready-for-agent` | `3-clanker-queue`    | Admitted to the agent-maintained queue         |
| `ready-for-human` | `3-human-queue`      | Admitted to the human-maintained queue         |
| `wontfix`         | `wontfix`            | Will not be actioned                           |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the
corresponding label string from this table.

## Related labels not in the canonical set

These exist in the tracker and carry meaning the five roles don't cover. Leave
them alone unless a skill's intent clearly matches:

- `4-review` — a pull request is awaiting review
- `blocked` — blocked on human input or an external dependency
- `hold` — intentionally paused
- `agent/contributor` — work done by the contributor agent

## Ownership boundary

Humans triage and approve; agents claim `3-clanker-queue` issues. Clankers is
authenticated Hive transport only, not merge authority. Never apply labels to or
open issues in `ublue-os/*`.

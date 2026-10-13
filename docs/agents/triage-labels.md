# Triage Labels & Prow Commands

This repository follows the org-wide [Prow](https://github.com/cncf/prow-github-actions)
workflow and label configuration from
[`projectbluefin/.project/prow.yaml`](https://github.com/projectbluefin/.project/blob/main/prow.yaml)
and [`projectbluefin/common`](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).

## Lifecycle and commands

1. **Filed:** Issue forms apply `needs-human` and a kind (`kind/bug`, `kind/feature`, `kind/cleanup`).
2. **Triage:** Maintainers/triagers set kind (`/kind ...`), area (`/area ...`), or priority (`/priority ...`).
3. **Accepted:** When scope is accepted and ready, comment `/triage accepted`.
4. **Agent pickup:** Maintainers remove `needs-human`. Hive assigns work only when `triage/accepted` is present and neither `needs-human` nor `blocked` is set.
5. **Blocked:** `/label blocked` / `/remove-label blocked`.

## PR review and merge

- Reviewers comment `/lgtm` (pushing new commits clears `lgtm`).
- Approvers in [`OWNERS`](../../OWNERS) comment `/approve`.
- Merges are processed on `lgtm` + `approved` + green checks (via Prow Tide / merge queue where enabled).
- `/hold` / `/hold cancel` blocks or unblocks merge.
## Ownership boundary

Humans triage and approve via `/triage accepted`, `/lgtm`, and `/approve`.
Clankers transports Hive assignments. Never write to `ublue-os/*`.

---
name: lab-runner-contract
version: "1.0"
last_updated: 2026-08-20
id: lab-runner-contract
one_line_purpose: Define the lab-runner tool contract that just verify enforces.
entry_point: docs/skills/lab-runner-contract.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: [container-standards]
tags: [lab-runner, contract, ci, tooling]
description: "The lab-runner shell-enabled capability contract — what ships, what is excluded, and the size budget. Use when adding or removing a tool in elements/lab-runner/."
metadata:
  type: policy
---

# Lab-Runner Capability Contract

`lab-runner` is the shell-enabled CI utility image for Argo Workflow steps — the
documented exception to distroless (see
[container-standards.md](container-standards.md), which states the policy; this
file is the authoritative tool inventory). The enforced gates live in the
Justfile `verify` recipe — **if this file and `just verify` disagree, the gate
is right and this file is stale.** All additions/removals update this file and
the gate in the same commit.

## Included

Sourced from `elements/lab-runner/lab-runner-stack.bst`:

| Tool | Source | Gated in `just verify` |
|------|--------|------------------------|
| bash, coreutils, terminfo db | base-stack | bash present; terminfo entries incl. `x/xterm-ghostty` |
| curl, git, jq, python3 (+pyyaml), openssh | FSDK components | — |
| diffutils, file, findutils, gawk, gzip, less, patch, procps, tar, which | FSDK components | standard-userland gate (all ten); gzip additionally via a real `.tar.gz` round trip |
| shellcheck, hadolint, actionlint | `lab-runner/*.bst` | linter-suite gate (all three execute) |
| argo, just, kubectl | `lab-runner/*.bst` | CLI-contract gate (`--entrypoint` execution) |
| yq | `lab-runner/yq.bst` | — |
| nginx | `lab-runner/nginx.bst` | — |

`gzip` is not optional beside `tar`: GNU tar execs the `gzip` binary for
`.tar.gz` streams, so `tar --version` passing says nothing about `tar -xzf`
(#87). The gate therefore round-trips a real archive.

## Explicitly excluded

Re-adding one of these requires new rationale here first.

| Tool | Reason |
|------|--------|
| pre-commit | Framework overhead for single-step CI; hooks belong in the checkout environment, not the runner |
| Any runtime package manager (apk/apt/dnf/pip) | Shell-enabled does not mean mutable; a missing tool is a contract change, not a runtime install |

## Size budget

`just verify` enforces `MAX_BYTES=640 MiB` against `podman image inspect
.Size` — **uncompressed**, not compressed. A PR that grows the image must name
the capability gained; a PR that crosses the ceiling must raise it in the same
commit with the measurement in the PR body.

## Not machine-readable (yet)

Issue #94 asks for a `capabilities.yml` that *generates* the gate's tool lists
instead of hardcoded `for tool in ...` loops in the Justfile. Until that lands,
this markdown is the contract and the Justfile loops are the enforcement.

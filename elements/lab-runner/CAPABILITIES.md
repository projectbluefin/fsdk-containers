# Lab-Runner Capability Contract

This document is the authoritative source for what the `lab-runner` container
provides, what it intentionally excludes, and why. All additions or removals
must update this file before the PR is merged.

## Design contract

`lab-runner` is a **shell-enabled CI utility container** for Argo Workflow
steps. It is not distroless: shell, standard GNU userland, and Python 3 are
first-class citizens. All tools are built by FSDK; there is no runtime package
manager (`apk`, `dnf`, `pip`) and no internet access during workflow
execution.

## Included tools

### Core utilities (POSIX / GNU userland)

| Tool | Source | Rationale |
|------|--------|-----------|
| bash | base-stack | Shell-enabled image requirement |
| curl | freedesktop-sdk | HTTP downloads, API calls |
| git | freedesktop-sdk | Source checkout |
| jq | freedesktop-sdk | JSON parsing in shell pipelines |
| python3 | freedesktop-sdk | Scripting, YAML/JSON processing |
| openssh | freedesktop-sdk | SSH clients (`ssh`, `scp`) |
| diffutils | freedesktop-sdk | `diff`, `cmp` for change detection |
| file | freedesktop-sdk | MIME-type detection |
| findutils | freedesktop-sdk | `find`, `xargs` |
| gawk | freedesktop-sdk | `awk` for text processing |
| less | freedesktop-sdk | Pager for CI log inspection |
| patch | freedesktop-sdk | Apply unified diffs |
| procps | freedesktop-sdk | `ps`, `kill` for process management |
| tar | freedesktop-sdk | Archive extraction (includes gzip) |
| which | freedesktop-sdk | Tool presence detection in scripts |

### YAML tooling

| Tool | Source | Rationale |
|------|--------|-----------|
| python3-pyyaml | freedesktop-sdk | `import yaml` for Python scripts |
| yq | lab-runner/yq.bst | Shell YAML pipelines (GH Actions workflows, K8s manifests) |

### CI / Kubernetes tooling

| Tool | Source | Rationale |
|------|--------|-----------|
| argo | lab-runner/argo.bst | Submit and monitor Argo Workflows |
| just | lab-runner/just.bst | Task runner (Justfile recipes) |
| kubectl | lab-runner/kubectl.bst | Kubernetes API access |
| nginx | lab-runner/nginx.bst | Static file serving in workflow steps |

## Explicitly excluded tools

These tools have been considered and rejected. Re-opening a PR to add them
requires updating this table with new rationale; the previous decision stands
until overridden here.

| Tool | Rejected in | Reason |
|------|-------------|--------|
| pre-commit | PR #92 | Framework overhead not worth it for single-step CI; hooks are better run in the checkout environment, not the runner container |
| hadolint | PR #92 (reconsidered PR #100) | Dockerfile linting belongs in the repo-level CI step using the upstream image, not baked into the runner |

> **Note:** If PR #100 (shellcheck, hadolint, actionlint) merges, update the
> included-tools table and remove hadolint from the exclusion list above.

## Size budget

Target: compressed image ≤ **500 MB**. Any PR that pushes the compressed
size above this threshold must include a documented exception (name the
specific capability gained and why it justifies the size increase) in the PR
body and in this table.

| Baseline | Date | Compressed size |
|----------|------|-----------------|
| lab-runner-runtime.bst | 2026-08-08 | _measure before merging #100_ |

## Change process

1. Add or remove an entry in the relevant table above.
2. Update `lab-runner-stack.bst` (or the appropriate `.bst` file) to match.
3. If removing: move the tool to the **Excluded** table with rationale.
4. Include a size delta estimate in the PR description.
5. This file must be updated in the same commit as the `.bst` change.

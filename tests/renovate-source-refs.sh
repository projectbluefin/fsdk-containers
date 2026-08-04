#!/usr/bin/env bash
# Regression check for versioned remote sources tracked by Renovate.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${repo_root}/.github/workflows/renovate-source-refs.yml"

for element in just kubectl argo; do
    file="${repo_root}/elements/lab-runner/${element}.bst"
    test -f "${file}"
    grep -q 'renovate: datasource=github-releases' "${file}"
    grep -Eq '^[[:space:]]+[a-z_]+_version:' "${file}"
    count="$(grep -E '^[[:space:]]+ref: [0-9a-f]{64}$' "${file}" | wc -l)"
    test "${count}" -eq 2
    grep -q "elements/lab-runner/${element}.bst" "${workflow}"
done

grep -q "github.event.pull_request.user.login == 'renovate\[bot\]'" "${workflow}"
grep -q 'just bst source track elements/lab-runner/just.bst' "${workflow}"
grep -q 'just bst source track elements/lab-runner/kubectl.bst' "${workflow}"
grep -q 'just bst source track elements/lab-runner/argo.bst' "${workflow}"
printf '%s\n' 'Renovate source-ref wiring: PASS'

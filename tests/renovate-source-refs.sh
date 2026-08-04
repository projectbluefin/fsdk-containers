#!/usr/bin/env bash
# Regression checks for the Renovate/BuildStream source-ref reconciliation workflow.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${repo_root}/.github/workflows/renovate-source-refs.yml"

for element in just kubectl argo; do
    file="${repo_root}/elements/lab-runner/${element}.bst"
    test -f "${file}"
    grep -q 'renovate: datasource=github-releases' "${file}"
    grep -Eq '^[[:space:]]+[a-z_]+_version:' "${file}"
    test "$(grep -Ec '^[[:space:]]+ref: [0-9a-f]{64}$' "${file}")" -eq 2
done

grep -q 'pull_request_target:' "${workflow}"
grep -q '^permissions: {}$' "${workflow}"
grep -q "github.event.pull_request.user.login == 'mergeraptor\[bot\]'" "${workflow}"
grep -q "startsWith(github.event.pull_request.head.ref, 'renovate/')" "${workflow}"
grep -q 'github.event.pull_request.head.repo.full_name == github.repository' "${workflow}"
grep -q '^      contents: read$' "${workflow}"
grep -q '^      pull-requests: read$' "${workflow}"
grep -q 'repository: \${{ github.repository }}' "${workflow}"
grep -q 'persist-credentials: false' "${workflow}"
! grep -q 'head.repo.full_name }}' "${workflow}"
grep -q 'just bst source track' "${workflow}"
grep -q 'git push .*GITHUB_REPOSITORY' "${workflow}" || grep -q 'HEAD:refs/heads/\${BRANCH}' "${workflow}"
printf '%s\n' 'Renovate source-ref wiring: PASS'

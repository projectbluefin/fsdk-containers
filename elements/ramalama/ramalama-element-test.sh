#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

graph="$(just bst show --deps all oci/ramalama.bst)"

for required in \
    'ramalama/ramalama.bst' \
    'ramalama/ramalama-stack.bst' \
    'ramalama/ramalama-runtime.bst' \
    'base/base-stack.bst' \
    'freedesktop-sdk.bst:components/ca-certificates.bst' \
    'freedesktop-sdk.bst:components/tzdata.bst' \
    'freedesktop-sdk.bst:components/python3.bst' \
    'freedesktop-sdk.bst:components/python3-jinja2.bst' \
    'freedesktop-sdk.bst:components/python3-pyyaml.bst'
do
    if ! grep -Fq "$required" <<<"$graph"; then
        echo "FAIL: missing ${required} from oci/ramalama.bst dependency graph" >&2
        exit 1
    fi
done

echo "OK: oci/ramalama.bst dependency graph includes the expected RamaLama runtime components"

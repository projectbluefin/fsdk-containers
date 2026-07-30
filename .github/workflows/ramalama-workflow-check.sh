#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

build_workflow=".github/workflows/build.yml"
justfile="Justfile"

require_grep() {
    local pattern="$1"
    local file="$2"
    local message="$3"
    if ! grep -Eq "$pattern" "$file"; then
        echo "FAIL: ${message}" >&2
        exit 1
    fi
}

if [[ "$(grep -Ec 'image: \[[^]]*ramalama[^]]*\]' "$build_workflow")" -lt 2 ]]; then
    echo "FAIL: ramalama must be present in both build.yml image matrices" >&2
    exit 1
fi

require_grep 'oci/ramalama\.bst' "$justfile" 'ramalama must be part of just validate'
require_grep 'ramalama\)\s+ELEMENT="oci/ramalama\.bst";\s+SPDX_NAME="ramalama"' "$justfile" 'ramalama must be part of just sbom'
require_grep 'for img in .*ramalama; do' "$justfile" 'ramalama must be part of just sboms'

echo "OK: RamaLama build, manifest, and SBOM wiring is present"

#!/usr/bin/env bash
# Seed printing/base.bst from the signed printing-base-devel bundle
# (docs/skills/printing-base.md, consumer contract rule 4).
#
# Usage: ARCH=<x86_64|aarch64> seed.sh
#
# Runs in the consumer's checkout. Never fails once ARCH is set: every error
# falls through to a local build of the base, so the exit status is always 0
# and problems surface as GitHub `::warning::` lines. The bundle is only
# unpacked into the BuildStream cache after `cosign verify` accepts the exact
# digest that is then copied.
set -uo pipefail

: "${ARCH:?ARCH must name the BuildStream target arch (x86_64 or aarch64)}"

base=fsdk-containers.bst:printing/base.bst
show() {
  just bst -o arch "$ARCH" show --deps none --format "$1" "$base" 2>/dev/null |
    tail -n 1 | sed 's/\x1b\[[0-9;]*m//g'
}

KEY="$(show '%{full-key}')"
if [[ ! "$KEY" =~ ^[0-9a-f]{64}$ ]]; then
  echo "::warning::printing base: cannot compute the ${ARCH} key; building it locally"
  exit 0
fi
if [[ "$(show '%{state}')" == cached ]]; then
  echo "printing base ${ARCH}-${KEY} is already cached"
  exit 0
fi
if ! ARCH="$ARCH" KEY="$KEY" bash -euo pipefail <<'SEED'
REPO=ghcr.io/projectbluefin/printing-base-devel
DIGEST="$(skopeo inspect --format '{{.Digest}}' "docker://${REPO}:${ARCH}-${KEY}")"
# Only printing-base.yml on main publishes the bundle; a signature from any
# other workflow or branch is not accepted.
cosign verify \
  --certificate-identity 'https://github.com/projectbluefin/fsdk-containers/.github/workflows/printing-base.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "${REPO}@${DIGEST}" >/dev/null
# Copy exactly the verified digest; never touch podman storage.
bundle="$(mktemp -d)"
trap 'rm -rf "${bundle}"' EXIT
skopeo copy "docker://${REPO}@${DIGEST}" "dir:${bundle}"
layer="$(jq -r '.layers[0].digest' "${bundle}/manifest.json" | cut -d: -f2)"
tar -C ~/.cache/buildstream -xf "${bundle}/${layer}"
SEED
then
  echo "::warning::printing base: seeding ${ARCH}-${KEY} failed; building it locally"
elif [[ "$(show '%{state}')" != cached ]]; then
  echo "::warning::printing base: ${ARCH}-${KEY} not verified or not cached after seeding; building it locally"
else
  echo "printing base seeded from ${ARCH}-${KEY}"
fi
exit 0

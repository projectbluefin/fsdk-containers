---
name: printing-base
version: "1.0"
last_updated: 2026-09-25
id: printing-base
one_line_purpose: Build, publish, and consume the shared printing base (printing/base.bst) for the printer applications.
entry_point: docs/skills/printing-base.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: [bst-junctions, signing-and-sbom]
tags: [buildstream, printing, cups, junctions, cache-keys, supply-chain]
description: "The shared printing base for the printer applications: printing/base.bst contents, cache-key isolation of its FSDK patch, the signed printing-base-devel CAS bundle, and the consumer contract."
metadata:
  type: reference
  context7-sources:
    - /apache/buildstream
    - /sigstore/cosign
---

# Printing base

`elements/printing/base.bst` is the one CUPS provider for the printer
applications (ghostscript, gutenprint, hplip, ps). It is a `kind: stack` of:

| Element | Source |
|---|---|
| `freedesktop-sdk.bst:components/cups-daemon-only.bst` (+ `cups.bst`) | FSDK, patched |
| `freedesktop-sdk.bst:components/cups-filters.bst`, `libcupsfilters.bst` | FSDK, patched |
| `freedesktop-sdk.bst:components/ghostscript.bst` | FSDK, patched |
| `freedesktop-sdk.bst:components/libppd.bst`, `mutool.bst` | FSDK |
| `freedesktop-sdk.bst:components/avahi-printing.bst` | added by the patch |
| `printing/pappl.bst` (tag pin), `printing/pappl-retrofit.bst` (commit pin) | this repo |

The customizations are `patches/freedesktop-sdk/0002-printing-*.patch`
(ghostscript-printer-app's `0001-customize-cups-for-printer-application.patch`
at the same FSDK pin) plus the source patch queues in `patches/printing/`,
staged into the junction by `elements/freedesktop-sdk.bst`.

## Why no other image's cache key moves

A junction patch changes the key of the elements whose files it changes and
their reverse dependencies, nothing else. No image here depends on cups,
cups-filters, libcupsfilters, libppd or ghostscript. It does depend on avahi:
`_private/avahi-base.bst` -> `avahi-libs` -> `ostree` -> `skopeo` feeds
`oci/skopeo.bst` and `oci/lab-runner.bst`. So the patch never edits
`avahi-base.bst`. It adds `_private/avahi-printing-base.bst`, which includes
`avahi-base.bst` with `(@)` and only overrides `conf-local`, and
`avahi-printing.bst`, which filters it. Included elements still need their own
`kind:`, because BuildStream reads `kind` before it processes includes.

Re-prove it after any change to the patch. With the patch removed and then
applied, run this on both arches for every element under `elements/` except
the junctions. The two outputs must be identical:

```bash
just bst -o arch x86_64 show --deps all --format '%{name}@@%{full-key}' <elements...>
```

Measured 2026-09-25: all 514 keys were unchanged on x86_64 and aarch64.
Patching `avahi-base.bst` in place instead moved 12 keys, including
`oci/skopeo.bst` and `oci/lab-runner.bst`.

Do not stage `components/avahi.bst` alongside `avahi-printing.bst`: both
install `avahi-daemon`.

## printing-base-devel bundle

`.github/workflows/printing-base.yml` runs on push to `main`, nightly, and
`workflow_dispatch`. It never runs on pull requests, where `just validate` only
`bst show`s the element. For each arch, `just printing-base-bundle` starts
from a clean cache, runs `bst artifact pull --deps all` and then
`bst build printing/base.bst`, and tars `artifacts/refs` and `cas/objects`.
That is the artifact proto plus the CAS objects it names, which is what makes
an artifact "cached". The tar becomes the single layer of a `FROM scratch`
image.

- `ghcr.io/projectbluefin/printing-base-devel:<arch>-<full-key>` and
  `<arch>-latest`, from `main` only. Any other ref pushes
  `<arch>-test-<run_id>`.
- Keyless cosign signature on the digest (GitHub OIDC).
- `ghcr-cleanup.yml` keeps the newest 5 tagged bundles per arch.

It is build-time only: it keeps every split domain, including headers, `.pc`
files and static libs. It is never runnable and never a base layer, and it
has no catalog record.

## Consumer contract

1. Junction fsdk-containers at a pinned commit. Add no patches, no
   `overrides`, and no options besides `arch: '%{arch}'`. Reference FSDK only
   through `fsdk-containers.bst:freedesktop-sdk.bst:...`. A second FSDK
   junction would be a second CUPS.
2. Build-depend on `fsdk-containers.bst:printing/base.bst` (devel). Compose
   the final OCI element from runtime domains only: `exclude` at least
   `devel`, `debug`, `doc`, `static-blocklist`.
3. Keys must match. Per arch, these two commands print the same value:
   `bst show --deps none --format '%{full-key}' printing/base.bst` in
   fsdk-containers at the pinned ref, and
   `bst show --deps none --format '%{full-key}' fsdk-containers.bst:printing/base.bst`
   in the consumer. This was verified 2026-09-25 against a scratch consumer
   project (both arches equal).
4. Seed the cache only from a verified digest. If verification fails, build
   locally and never extract:

   ```bash
   REPO=ghcr.io/projectbluefin/printing-base-devel
   podman pull "${REPO}:${ARCH}-${KEY}"
   DIGEST="$(podman image inspect --format '{{.Digest}}' "${REPO}:${ARCH}-${KEY}")"
   if cosign verify \
        --certificate-identity-regexp '^https://github.com/projectbluefin/fsdk-containers/.github/workflows/' \
        --certificate-oidc-issuer https://token.actions.githubusercontent.com \
        "${REPO}@${DIGEST}" >/dev/null; then
     ctr="$(podman create "${REPO}@${DIGEST}" /none)"
     podman export "${ctr}" | tar -C ~/.cache/buildstream -xf - artifacts cas
     podman rm "${ctr}"
   fi   # else: fall through to a normal local build
   ```

   BuildStream trusts `artifacts/refs` as given, so the signature is the
   trust boundary.
5. Add a no-devel-content check to `just verify`:

   ```bash
   root="$(mktemp -d)"; podman export "$(podman create "${IMAGE}" /none)" | tar -C "${root}" -xf -
   bad="$(cd "${root}" && find . \( -path ./usr/include -o -name '*.a' -o -name '*.la' \
         -o -type d -name pkgconfig -o -type d -name cmake \) -print -quit)"
   [ -z "${bad}" ] || { echo "devel content in ${IMAGE}: ${bad}" >&2; exit 1; }
   ```

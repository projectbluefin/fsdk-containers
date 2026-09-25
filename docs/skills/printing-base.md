---
name: printing-base
version: "1.1"
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
`bst show`s the elements. For each arch, `just printing-base-bundle` runs
`bst build printing/base.bst printing/foomatic-db.bst` in a clean cache. That pulls whatever a
configured remote serves and builds the rest. Only the artifacts that were
built go into the bundle: an element is bundled when the cache holds a build
log for its key. `scripts/printing_base_bundle.py` walks each bundled
artifact's proto and lists its refs (strong and weak key) plus the CAS
objects `Artifact.query_cache()` needs: the `files` tree, the metadata, the
public data and the logs. That list is tarred as the single layer of a
`FROM scratch` image.

`printing/foomatic-db.bst` goes in the same bundle. It is a stack of FSDK's
`components/foomatic-db.bst`, which build-depends on the patched CUPS, so
its key moved and no remote serves it. It is deliberately not part of
`base.bst`: only the applications that ship PPDs (ghostscript, ps) depend on
it. Of the 51 FSDK elements the four printer applications reference, the
patch moves exactly cups, cups-daemon-only, cups-filters, libcupsfilters,
libppd, ghostscript (all in `base.bst`) and foomatic-db (checked 2026-09-25
by diffing `bst show --deps none --format '%{full-key}'` with and without
the patch, on both arches). A consumer that starts using another FSDK element
whose closure includes the patched stack needs a `printing/` stack for it
here, added to the bundle's targets in `just printing-base-bundle`.
Consumers depend on `fsdk-containers.bst:printing/foomatic-db.bst`. The tag
carries only `base.bst`'s key. foomatic-db's key depends on the same junction
and patch, so it moves with it, but an edit to `printing/foomatic-db.bst`
alone does not change the tag.

The bundle build ignores project source caches and fetches sources from
`cache.projectbluefin.io` (or upstream), because the FSDK source cache
stalls.

Everything else in the closure stays on the remotes (gbm.gnome.org,
cache.freedesktop-sdk.io, cache.projectbluefin.io), and consumers pull it
from there as usual.

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
   DIGEST="$(skopeo inspect --format '{{.Digest}}' "docker://${REPO}:${ARCH}-${KEY}")"
   if cosign verify \
        --certificate-identity-regexp '^https://github.com/projectbluefin/fsdk-containers/.github/workflows/' \
        --certificate-oidc-issuer https://token.actions.githubusercontent.com \
        "${REPO}@${DIGEST}" >/dev/null; then
     skopeo copy "docker://${REPO}@${DIGEST}" dir:/tmp/bundle
     layer="$(jq -r '.layers[0].digest' /tmp/bundle/manifest.json | cut -d: -f2)"
     tar -C ~/.cache/buildstream -xf "/tmp/bundle/${layer}"   # tar detects the gzip
     rm -rf /tmp/bundle
   fi   # else: fall through to a normal local build; never fail the job here
   ```

   This never touches podman storage. `skopeo copy` by digest checks every
   blob against the signed manifest.
   BuildStream trusts `artifacts/refs` as given, so the signature is the
   trust boundary.
5. Add a no-devel-content check to `just verify`. License texts under
   `/usr/share/licenses` are pruned from the check and never deleted:

   ```bash
   root="$(mktemp -d)"; podman export "$(podman create "${IMAGE}" /none)" | tar -C "${root}" -xf -
   bad="$(cd "${root}" && find . -path ./usr/share/licenses -prune -o \( -path ./usr/include \
         -o -name '*.a' -o -name '*.la' -o -type d -name pkgconfig -o -type d -name cmake \) -print -quit)"
   [ -z "${bad}" ] || { echo "devel content in ${IMAGE}: ${bad}" >&2; exit 1; }
   ```

## Consumer CI wiring — the junction tracker

Each consumer carries one `update-base.yml`: it runs
`just bst source track fsdk-containers.bst`, rewrites the junction `ref:`, and
opens or refreshes the bump PR. It writes with a Mergeraptor installation
token, never `GITHUB_TOKEN` — a PR opened with the latter runs no checks at all.

All four printer apps are **forks** of `OpenPrinting/*`, and that is what breaks
the mint there. With only `app-id`/`private-key`, `create-github-app-token`
resolves the installation through `GET /repos/{owner}/{repo}/installation`,
which 404s on a fork (`Not Found -
get-a-repository-installation-for-the-authenticated-app`) even though the app is
installed org-wide and `mergeraptor[bot]` is already opening Renovate PRs in
that same repo. Pass `owner:` — and *only* `owner:`:

```yaml
- name: Mint Mergeraptor token
  id: app-token
  uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
  with:
    app-id: ${{ secrets.MERGERAPTOR_APP_ID }}
    private-key: ${{ secrets.MERGERAPTOR_PRIVATE_KEY }}
    owner: ${{ github.repository_owner }}
    permission-contents: write
    permission-pull-requests: write
```

`owner:` + `repositories:` does not fix it: as soon as `repositories:` is set
the action is back on the per-repository endpoint and 404s the same way.
`owner:` alone mints for the whole installation, so the `permission-*` inputs
are what keep the token narrow. No org-admin change is needed. Symptom,
evidence and the four affected repos: #331.

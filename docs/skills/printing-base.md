---
name: printing-base
version: "1.4"
last_updated: 2026-09-27
id: printing-base
one_line_purpose: Build, publish, and consume the shared printing base (printing/base.bst) for the printer applications.
entry_point: docs/skills/printing-base.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: [bst-junctions, signing-and-sbom]
tags: [buildstream, printing, cups, junctions, cache-keys, supply-chain, github-runners, apparmor]
description: "The shared printing base for the printer applications: printing/base.bst, cache-key isolation of its FSDK patch, the signed printing-base-devel bundle, the consumer contract, the shared slim recipe, and the ubuntu-24.04 runner pin."
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
| `freedesktop-sdk.bst:components/ghostscript.bst` | FSDK, patched (headless `--without-x`, no GhostPDL PCL/XPS) |
| `freedesktop-sdk.bst:components/libppd.bst` | FSDK |
| `freedesktop-sdk.bst:components/avahi-printing.bst` | added by the patch |
| `printing/pappl.bst` (tag pin), `printing/pappl-retrofit.bst` (commit pin) | this repo |

Opt-in elements outside `base.bst`:
- `printing/foomatic-db.bst`: FSDK `components/foomatic-db.bst` stack. Built
  against the patched CUPS. Deliberately not in `base.bst`: only applications
  that ship PPDs (ghostscript, ps) depend on it.
- `printing/mutool.bst`: FSDK `components/mutool.bst` stack. Moved out of
  `base.bst` to avoid shipping ~39 MiB into every appliance. Applications that
  prove a job needs the MuPDF renderer (`cfFilterMuPDFToPWG`) can depend on
  `fsdk-containers.bst:printing/mutool.bst` explicitly.

The customizations are `patches/freedesktop-sdk/0002-printing-*.patch`
(ghostscript-printer-app's `0001-customize-cups-for-printer-application.patch`
at the same FSDK pin) plus the source patch queues in `patches/printing/`,
staged into the junction by `elements/freedesktop-sdk.bst`. Ghostscript is
built without X11 (`--without-x`, dropping `xorg-lib-xt.bst`) and without
GhostPDL's PCL/XPS binaries (`--without-pcl`, `--without-xps`, `--without-gpdl`).

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
`FROM scratch` image. `tests/test_printing_base_bundle.py` covers that
selection on the host with stand-in protos; `just printing-base-check` runs
it, and `printing-base-bundle` runs it first.

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

The recipe retains `--network-retries 5` for errors marked temporary, but it
does **not** retry `git_repo` fetch failures. In the pinned
`buildstream-plugins-community` 2.3.1, `_git_utils.py` raises connection errors
(including read timeouts) as `SourceError` without `temporary=True`; the
[BuildStream SourceError API](https://docs.buildstream.build/master/buildstream.source.html#buildstream.source.SourceError)
defaults that field to `False`. Do not treat this flag as protection against
Git fetch timeouts: retrying those requires retrying the `bst build`
invocation itself or changing the plugin's error classification.

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
6. Apply the shared slim recipe and keep its gate. Include
   `include/slim-printing.yml` across the junction in the OCI script
   element and run its two variables before `build-oci`:

   ```yaml
   variables:
     (@):
       - fsdk-containers.bst:include/slim-printing.yml
   config:
     commands:
       - "%{slim-printing-commands}"
       - "%{slim-printing-gate-commands}"
       - |
         ... the app's own edits to /layer, then build-oci ...
   ```

   The gate fails the element if any path in
   `%{slim-printing-forbidden-paths}` survived, so a bump that stages a
   removed file again fails at build time on both arches. `just verify` must
   re-check the same list against the exported rootfs; the list is read from
   the element, so it moves with the junction pin:

   ```bash
   just bst show --deps none --format '%{vars}' oci/<app>.bst \
     | python3 -c 'import sys, yaml; print(yaml.safe_load(sys.stdin)["slim-printing-forbidden-paths"])' \
     > _slim-forbidden        # project-relative: the bst container only sees /src
   root="$(mktemp -d)"; podman export "$(podman create "${IMAGE}" /none)" | tar -C "${root}" -xf -
   shopt -s nullglob globstar; bad=0
   while IFS= read -r pattern; do
     [ -n "${pattern}" ] || continue
     for match in "${root}"/${pattern}; do
       # nullglob drops unmatched globs, not literal entries such as usr/bin/uconv
       [ -e "${match}" ] || [ -L "${match}" ] || continue
       echo "forbidden path in ${IMAGE}: ${match#"${root}"}" >&2; bad=1
     done
   done < _slim-forbidden
   rm -f _slim-forbidden; [ "${bad}" -eq 0 ]
   ```

   Put the app's own removals in the OCI element *after* the shared recipe
   and pair each with a line in the app's own forbidden list, never by
   editing the shared one.
7. Add a forbidden-path check to `just verify`. Enforce that interpreters and
   renderers never executed by the appliance (`gpcl6`, `gxps`, `mutool`) and
   Ghostscript's X11 toolkit dependency (`libXt`) are absent from the runtime rootfs:

   ```bash
   bad="$(cd "${root}" && find . \( -name gpcl6 -o -name gxps -o -name mutool -o -name 'libXt.so*' \) -print -quit)"
   [ -z "${bad}" ] || { echo "forbidden binary/library in ${IMAGE}: ${bad}" >&2; exit 1; }
   ```

   Note that `libX11` remains in the runtime closure through cairo (needed by
   poppler, cups-filters, and HPLIP's pycairo), so `libX11.so*` is not forbidden
   here. Configuring Ghostscript `--without-x` removes its direct X11 link
   and drops `xorg-lib-xt` (`libXt.so*`).

## Shared slim recipe — `include/slim-printing.yml`

The printer appliances are not distroless (bash entrypoint, pyppd PPD
archives are Python executables), so they cannot use
`slim-distroless-commands`. `include/slim-printing.yml` is their family
recipe: the OS-layer block of `include/slim.yml` minus the shell removal,
plus the runtime-closure bloat every printer app inherits from
`public-stacks/runtime-gnu.bst`. Measured 2026-09-26 against the published
amd64 images (rootfs extracted from the registry, removed bytes uncompressed):

| Removed | ghostscript | hplip | gutenprint |
|---|---|---|---|
| ICU (`libicudata` 31.6 MiB) + `libxml2` + `libharfbuzz-icu`, their CLIs and Python bindings | 42.3 | 42.3 | 42.3 |
| gcc sanitizer / Fortran / quadmath runtimes | 9.2 | 9.2 | 9.2 |
| Python `.opt-1.pyc` / `.opt-2.pyc` | 19.6 | 25.9 | — |
| Python stdlib tail (`ensurepip`, `_pyrepl`, `pydoc_data`, `unittest`, …) + `setuptools`/`mako`/`markdown`/`markupsafe` | 4.1 | 12.6 | — |
| gconv long tail, `usr/share/i18n` localedef inputs, `locale-archive` | 7.8 | 7.8 | 22.8 |
| runtime-gnu CLIs no printer path executes (ICU/gi/fc/hb/jpeg/tiff/webp/gnutls/selinux tools, `sqlite3`, `openssl`, …) | 13.2 | 13.2 | 13.0 |
| libraries outside every app's NEEDED closure (`libhwy_contrib`, `libturbojpeg`, `libharfbuzz-subset`, `libsepol`, C++ wrappers, xcb extensions, …) | 11.9 | 11.9 | 11.9 |
| **Total** | **108.0** | **122.8** | **99.2** |

Rootfs 407 → 299 MiB (ghostscript), 499 → 375 (hplip), 419 → 320
(gutenprint). After the recipe every remaining ELF's `NEEDED` still
resolves, and `gs`, `foomatic-rip`, `pdftops`, `ippfind`, `dbus-daemon`,
`avahi-daemon`, `curl`, `gpg`, `hp-probe`, the pyppd archives (`list`/`cat`)
and `python3` importing `distro`, `dbus`, `gi`, `cairo`, `PIL` behave the
same before and after.

Why ICU can go: its only consumers are the ICU CLIs, `libharfbuzz-icu` and
`libxml2`, and `libxml2`'s only consumers are `xmllint`/`xmlcatalog` and the
Python bindings. Gutenprint parses XML with its bundled mxml; fontconfig,
avahi, dbus and pyexpat link expat. A `readelf -d` NEEDED walk over every
executable, filter, backend and Python extension in the three images shows
nothing else reaching it.

What the shared recipe deliberately does **not** touch, because at least one
app needs it: `libcairo`/`libpixman`/`libgio`/`libgobject`/`libgirepository`
(HPLIP's pygobject + pycairo), `libgcrypt` and `libsqlite3` (HPLIP's gpg),
poppler's CLIs (`pdftops` is cups-filters' hybrid renderer), `libX11`
(pulled by cairo for poppler/cups-filters and pycairo; Ghostscript's direct X devices dropped in #340), `usr/share/locale` (gutenprint keeps the
domain for translated PPDs), `usr/share/misc/magic.mgc` (`file`, ghostscript
only), perl and `which` (HPLIP). Those are per-app removals for the app's own
OCI element. glibc NSS modules, p11-kit trust modules, OpenSSL providers and
`libmvec` are dlopen'd and invisible to a NEEDED walk: never add them.

The remaining lever is the closure itself: every consumer stack depends on
`public-stacks/runtime-gnu.bst` wholesale, so the recipe deletes what a
narrower component set would never stage. Replacing it with the components
each app actually needs is consumer work, measured per app with
`podman export` + `readelf -d`, and it shrinks the recipe's job rather than
changing its contract.

`tests/test_slim_printing.py` runs the recipe and the gate against a
synthetic layer holding one instance of every forbidden glob plus a keep-list
of what the apps need, and proves the gate fails closed. It is the only thing
in this repository that executes the fragment; `just catalog-check` and
`image-catalog.yml` run it.

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

## Consumer CI runners: keep BuildStream jobs on ubuntu-24.04

The printer-app repositories build with `just bst ...` on GitHub-hosted
runners. When Renovate bumped their `runs-on` from `ubuntu-24.04` to
`ubuntu-26.04` the builds broke (projectbluefin/fsdk-containers#332). The
failure is not a BuildStream, podman, or buildbox-fuse regression; it is a
host AppArmor policy leaking into the sandbox.

### Root cause

Ubuntu 26.04 runner images (apparmor 5.0.2, kernel 7.0) ship
`/etc/apparmor.d/gs`, an **enforcing** profile attached to `/usr/bin/gs`.
Ubuntu 24.04 (apparmor 4.0.1) has no such profile. AppArmor attaches a
profile on `exec` by path, and the `--privileged` podman container plus
`buildbox-run-bubblewrap`'s user namespace do not stop that: the FSDK
sandbox has its own `/usr/bin/gs`, the exec matches the host profile, and gs
runs confined. The profile only allows reads under `/usr/share/**`,
`/var/lib/ghostscript/**`, `/etc/paperspecs` and fonts, plus owner
read/write under `@{HOME}/**.<gs ext>`, `/tmp`, `/mnt/**` and `/media/*/**`.
The BuildStream build root is `/buildstream/<project>/<element>/` on a
buildbox-fuse mount, so every gs open there fails:

```
openat(AT_FDCWD, "testpage.ps", O_RDONLY)                        = -1 EACCES
openat(AT_FDCWD, "testpage.pdf", O_RDWR|O_CREAT|O_TRUNC, 0666)   = -1 EACCES
GPL Ghostscript: **** Could not open the file testpage.pdf .
```

Shell tools in the same sandbox (`cat`, `cp`, `touch`, `mkdir`) read and
write the same paths fine, and gs itself works when both its input and
output live under `/tmp`. Only elements that *execute* `gs` at build time
are affected (e.g. gutenprint's `printer-app/runtime-files.bst` rendering
`testpage.ps` to PDF). This repository's own `printing-base.yml` job passes
on ubuntu-26.04 because none of `printing/base.bst`'s elements run gs while
building; the runner label there is not a signal that consumers can move.

Evidence: gutenprint-printer-app run 36158590555 (26.04, only
`runtime-files.bst` fails) vs 36158593750 (24.04, same cache key `42f6a2c8`
passes); in-sandbox strace and `aa-status` probes on both images.

### What consumers must do

1. Pin every job that runs `just bst` (build, publish, verify) to
   `ubuntu-24.04`.
2. Stop Renovate from re-bumping it. The `github-runners` datasource is what
   proposes `ubuntu-26.04`; cap it in `renovate.json`:

   ```json
   {
     "packageRules": [
       {
         "description": "GitHub-hosted runners: stay on ubuntu-24.04 (26.04 ships an enforcing AppArmor gs profile that breaks gs inside the bst sandbox)",
         "matchDatasources": ["github-runners"],
         "matchPackageNames": ["ubuntu"],
         "allowedVersions": "<26"
       }
     ]
   }
   ```

   gutenprint-printer-app#52 and ps-printer-app#52 carry this rule;
   ghostscript-printer-app and hplip-printer-app must add the same one.
3. Renovate does not alter `fsdk-containers` runner pins from the consumer
   side, and this repository's `renovate.json` has no runner cap on purpose
   (see above). Do not copy the cap here unless an element in
   `printing/base.bst` starts executing gs during its build.

### If a job has to run on ubuntu-26.04

Unload the profile on the runner before the first `just bst`; it is host
policy, so nothing inside the element or `Justfile` can opt out of it:

```yaml
- name: Unload the AppArmor gs profile (Ubuntu 26.04 ships /etc/apparmor.d/gs)
  run: |
    if [ -f /etc/apparmor.d/gs ]; then
      sudo apparmor_parser -R /etc/apparmor.d/gs
    fi
```

Rewriting the element to copy its inputs to `/tmp`, run gs there and
install the result from `/tmp` also works, but ties the element to a
runner quirk; prefer the pin plus the Renovate cap.

The `rm: cannot remove '/buildstream/...': Read-only file system` line
quoted in #332 is not the failure. It is BuildStream's post-command
build-root cleanup and shows up on *successful* 26.04 builds as well (the
verification run below prints it right before `SUCCESS ... Running
commands`). The only 26.04-specific failure observed is the gs EACCES above.

Verified: on ubuntu-26.04 with the `gs` profile unloaded, the unmodified
`printer-app/runtime-files.bst` builds and caches (clubanderson fork run
36213750777); the same element fails on the same image with the profile
loaded.

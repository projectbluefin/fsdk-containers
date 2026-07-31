---
name: ramalama-image
description: >
  Source, build, verification, and consumer contract for the fsdk-containers
  RamaLama helper image.
metadata:
  context7-sources:
    - /apache/buildstream
---

# RamaLama Helper Image

Use this skill when updating `elements/ramalama/*`, `elements/oci/ramalama.bst`,
the RamaLama verify gates, or the consumer-facing contract in `README.md`.

## Source of truth

- **Upstream project:** `containers/ramalama`
- **Package source:** PyPI sdist `ramalama-0.23.0.tar.gz`
- **Pinned SHA-256:** `dc02b82e46ddd682cb1019c5d474c1caf48a38ca13798d6e92aa3b779e04ef04`
- **Build path:** build a wheel from the pinned sdist with FSDK Python tooling,
  then install it into `%{install-root}` with `python3 -m installer`.

This keeps the helper aligned with the official upstream Python distribution
while still composing the runtime from verified FSDK Python components instead
of maintaining an ad hoc package set.

## Verified FSDK component set

### Runtime

- `base/base-stack.bst`
- `freedesktop-sdk.bst:components/python3.bst`
- `freedesktop-sdk.bst:components/python3-jinja2.bst`
- `freedesktop-sdk.bst:components/python3-pyyaml.bst`
- `ramalama/ramalama.bst`

### Build-only

- `freedesktop-sdk.bst:components/python3-build.bst`
- `freedesktop-sdk.bst:components/python3-installer.bst`
- `freedesktop-sdk.bst:components/python3-setuptools.bst`
- `freedesktop-sdk.bst:components/python3-wheel.bst`

`argcomplete` is intentionally **not** part of the runtime stack. FSDK 25.08
does not ship a `python3-argcomplete` component, and RamaLama wraps the import
in `try/except` so shell completion support is optional rather than a hard
runtime dependency.

## Runtime boundary

The published image is a **helper-only control-plane image**:

- it ships the `ramalama` CLI and its static configuration/data files;
- it does **not** ship model weights;
- it does **not** ship GPU runtime containers;
- it expects a writable external RamaLama store mounted at
  `/var/lib/ramalama` when the helper runs as root (RamaLama's upstream
  root-user default);
- it requires host Podman/Docker access when consumers want RamaLama to pull and
  run accelerator-specific inference images.

The image also ships upstream `/usr/share/ramalama/ramalama.conf` and
`/usr/share/ramalama/shortnames.conf`. Those files are public, mutable defaults
only. If a consumer needs private endpoints, pinned runtime images, pinned
model refs, or a different store path, it must provide its own
`/etc/ramalama/ramalama.conf` or set `RAMALAMA_CONFIG` explicitly.

The helper image must stay distroless:

- no shell;
- no `pip` or other package-manager path;
- no shell completion or manpage payloads in the final rootfs.

## Local verification

Run the targeted checks from the repository root:

```bash
just validate
bash elements/ramalama/ramalama-element-test.sh
BUILD_IMAGE_NAME=ramalama just build
TMPDIR="$PWD/.tmp" BUILD_IMAGE_NAME=ramalama just verify
just sbom ramalama
```

`TMPDIR="$PWD/.tmp"` keeps local verification out of `/tmp` while the generic
`just verify` recipe still uses `mktemp`.

On the current x86_64 FSDK 25.08.14 build, the uncompressed local Podman image
size is about **104 MB**; `just verify` caps the helper at **160 MB** to leave
headroom for normal FSDK/runtime growth.

## Digest-first consumer contract

Consumers should pin all RamaLama-related artifacts immutably:

1. **Helper image:** use `ghcr.io/projectbluefin/ramalama@sha256:<manifest-digest>`,
   not a floating tag.
2. **Runtime image overrides:** upstream RamaLama defaults to
   `quay.io/ramalama/*:<major.minor>` tags via `version_tagged_image()`. If a
   consumer overrides `image`/`images.*`, prefer digest refs instead of mutable
   tags.
3. **Model catalog entries:** prefer immutable transport refs or catalog entries
   that resolve to a fixed artifact. Do not treat the shipped
   `shortnames.conf` as a production source of truth; it is an upstream public
   default and can change between RamaLama releases.

This image is suitable for donate-clanker only when the launcher owns the image
digest, store mount, consumer config, container-engine access, and cleanup
contract.

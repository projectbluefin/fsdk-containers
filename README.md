# fsdk-containers

**Bringing distroless patterns to [freedesktop-sdk](https://gitlab.com/freedesktop-sdk/freedesktop-sdk) (FSDK) containers.**

FSDK already maintains beautifully patched, reproducible builds of glibc and
every major runtime. This repo applies the distroless playbook to them — carve
out only the runtime, strip the bloat, ship slim by default — so you get a free,
OSS distroless suite that **inherits FSDK's CVE patching** instead of maintaining
a separate package set.

These containers are maintained for projectbluefin/fsdk usage for cluster ops, etc. Digital sovereignty isn't just for nations, this controls our supply chain. 

## Images

| Image | Size | Description |
| ----- | ---- | ----------- |
| `ghcr.io/projectbluefin/base` | ~40 MB | Distroless base: glibc, coreutils, CA certificates, timezone data. No shell, no package manager. Multi-arch: linux/amd64, linux/arm64. [¹](#base-contract) |
| `ghcr.io/projectbluefin/static` | ~40 MB | **Deprecated — currently identical to `base`.** Intended as a libc-free tier for `CGO_ENABLED=0` binaries, but it ships full glibc and differs from `base` by two files. Use `base` instead. See [#116](https://github.com/projectbluefin/fsdk-containers/issues/116). |
| `ghcr.io/projectbluefin/python` | ~45 MB | Distroless Python 3: Python runtime + pip, with dev/testing bloat pruned. No shell, no package manager. Multi-arch: linux/amd64, linux/arm64. |
| `ghcr.io/projectbluefin/skopeo` | — | Distroless Skopeo OCI image utility. No shell, no package manager. Multi-arch: linux/amd64, linux/arm64. |
| `ghcr.io/projectbluefin/buildah` | ~70 MB | Distroless Buildah: static Go binary compiled from source, linked against FSDK gpgme/libseccomp. No shell, no package manager. Multi-arch: linux/amd64, linux/arm64. |
| `ghcr.io/projectbluefin/qemu-img` | — | Distroless qemu-img disk image utility, compiled with OpenSSF-hardened flags. No shell, no package manager. Multi-arch: linux/amd64, linux/arm64. |
| `ghcr.io/projectbluefin/lab-runner` | — | **Deliberately shell-enabled** CI/CD utility container (bash, curl, git, jq, yq, python3 + PyYAML, kubectl) for Project Bluefin lab workflows. The one scoped exception to the no-shell rule among the OCI images. Multi-arch: linux/amd64, linux/arm64. |

<a name="base-contract"></a> **¹ Base image contract:** The base image is intentionally
shell-less but keeps coreutils. In FSDK 25.08, `runtime-minimal` still bundles bash
and coreutils together; the SLIM recipe removes only bash. In FSDK 26.08+, the
split becomes explicit: `runtime-minimal` drops both bash and coreutils, which move
to `public-stacks/runtime-gnu`. The distroless `base` image continues to compose
from `runtime-minimal` and therefore does not include bash; shell-enabled stacks
(lab-runner, brew) must add `runtime-gnu` when upgrading to FSDK 26.08+.

### Machine images (not distroless)

| Image | Size | Description |
| ----- | ---- | ----------- |
| `ghcr.io/projectbluefin/brew` | ~410 MB | Homebrew developer environment as a **systemd-nspawn machine image** (a `.tar.zst` rootfs for `machinectl import-tar`, **not** an OCI image). Full dev env: bash, ruby, git, curl, gcc, patchelf, systemd init + the linuxbrew prefix. The distroless/slim rules do **not** apply here — see [docs/skills/nspawn-machine-image.md](docs/skills/nspawn-machine-image.md). Built with `just export-brew`. |

## How it works

Each image is composed from raw FSDK `components/*` (never `platform.bst`),
then chiseled with a BuildStream `compose` element that drops every non-runtime
split-rule domain, and finally run through the **SLIM recipe** in the OCI script
step. The slim recipe removes the large runtime-domain bloat that has no FSDK
domain to exclude it: shell binaries, `terminfo`, gcc sanitizer/fortran runtimes,
the `gconv` charset long-tail, the glibc `locale-archive`, and leaked build tools.

It deliberately **keeps** the cheap crash-preventers — `tzdata`, a common charset
set, CA certificates — so `datetime`/TLS work out of the box without the wheel
gymnastics other distroless suites push onto you.

Pipeline: `stack` (deps) -> `compose` (chisel) -> `script` (slim + oci-builder).
See [docs/skills/slim-an-image.md](docs/skills/slim-an-image.md) for the recipe.

## Verify signatures

All published multi-arch images are keyless-signed with [cosign](https://docs.sigstore.dev/)
and ship an attached SPDX SBOM. Signing happens in the `oci-images.yml` reusable
workflow (called from `build.yml` — see docs/skills/ci-tooling/SKILL.md), so the
certificate identity below names that file, not `build.yml`. Verify a
main-branch build with:

    cosign verify ghcr.io/projectbluefin/base:25.08 \
      --certificate-identity "https://github.com/projectbluefin/fsdk-containers/.github/workflows/oci-images.yml@refs/heads/main" \
      --certificate-oidc-issuer "https://token.actions.githubusercontent.com"

(Builds triggered from other refs, e.g. dispatch test builds, are signed with the
corresponding branch ref in the certificate identity.)

GitHub also publishes a registry-backed build provenance attestation for each
image. Verify it with the GitHub CLI:

    gh attestation verify oci://ghcr.io/projectbluefin/base:25.08 \
      -R projectbluefin/fsdk-containers

For reproducible audits, replace the tag with the exact manifest digest.

## Versioning

There is no application version for a base image, so the version axis is the
FSDK release. We track upstream FSDK releases and active development/beta branches
so users can test upcoming FSDK features early. Tags are derived automatically from
the pinned junction ref in `elements/freedesktop-sdk.bst`:

- `:25.08` or `:26.08` -- FSDK minor line (the most rolling tag published)
- `:25.08.14` -- FSDK point release (immutable: once published, CI never overwrites a point-release tag)
- `:26.08beta.1` / `:26.08rc.1` -- pre-release/beta tags (published for every upstream dev/beta branch)

There is deliberately **no `:latest`**. A rolling alias lets a consumer deploy
an unpinned image and have it change underneath them without any signal; the
minor line is the most permissive tag we publish, so every consumer has to
state how much drift it accepts. Pin the point release, or a digest, when even
that is too much.

Every image self-declares its base via `io.projectbluefin.fsdk.version` and
`io.projectbluefin.fsdk.ref` labels.

## Build locally

Requires `podman` and [`just`](https://github.com/casey/just). BuildStream runs
inside the FSDK `bst2` container -- nothing to install.

    just validate        # resolve the element graph
    just build           # build + load ghcr.io/projectbluefin/base:build
    just verify          # assert distroless + certs + tzdata
    just tags            # show derived tags

All image recipes are independently selectable from the canonical
`elements/targets.json` manifest; for example:

    BUILD_IMAGE_NAME=python just build
    BUILD_IMAGE_NAME=python just verify

The manual **Build images** workflow likewise accepts an optional `image`
input, so one target can fan out to native x86_64 and aarch64 runners without
building a separate repository or waiting for unrelated image targets.

By default `just bst` submits build actions to the ghost cluster's BuildBarn
remote-execution grid instead of building on your machine (and fails loudly if
the cluster is unreachable). Use `BST_LOCAL=1 just build` for explicit local
execution — see [docs/skills/remote-execution.md](docs/skills/remote-execution.md).

## Homebrew systemd-nspawn container

For a full developer environment container booted by `systemd-nspawn` instead of a distroless OCI image, we provide the `brew` machine image.

### 1. Build and install

The build process produces a `.tar.zst` rootfs, imports it into `machinectl`, creates a dedicated `/home/linuxbrew` folder on your host, and configures the `systemd-nspawn` sandbox settings (requires `sudo`):

    just install-brew

This runs `build-brew`, `export-brew`, and `verify-brew` before importing it as a systemd machine named `homebrew`.

### 2. Run commands

Execute brew commands inside the sandboxed container from your host shell:

    just run-brew info
    just run-brew install hello

### 3. Uninstall

Stop the container, remove the machine image, and clean up sandbox settings:

    just uninstall-brew

Please report any issues or feedback you encounter while using the Homebrew nspawn container!

## Custom Builds and Caching

You can fork/clone this repository to run your own custom builds and maintain them in GitHub Actions.

The repository includes pre-configured public, read-only cache servers (from GNOME and Project Bluefin) in `project.conf` so you can build on top of pre-compiled freedesktop-sdk components without rebuilding everything from scratch.

For instructions on configuring your own push caches (local or remote CAS) or setting up GitHub Actions caching, see the **[Custom Builds and Caching Guide](docs/skills/custom-builds-and-caching.md)**.

## License

Apache-2.0.

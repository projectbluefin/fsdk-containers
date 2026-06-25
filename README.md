# fsdk-containers

Distroless OCI base images carved from [freedesktop-sdk](https://gitlab.com/freedesktop-sdk/freedesktop-sdk)
(FSDK) using BuildStream. A free, OSS alternative to commercial distroless
suites: images inherit FSDK's existing CVE patching and reproducible builds
instead of maintaining a separate package set.

## Images

| Image | Description |
| ----- | ----------- |
| `ghcr.io/projectbluefin/base` | Distroless base: glibc, CA certificates, timezone data. No shell, no package manager. Multi-arch: linux/amd64, linux/arm64. |

## How it works

Each image is composed from raw FSDK `components/*` (never `platform.bst`),
then chiseled with a BuildStream `compose` element that drops every non-runtime
domain. The OCI script step also explicitly removes shell binaries (`bash`, `sh`)
because the FSDK `shells` domain covers only `/usr/share/fish` and `/usr/share/zsh`
data; the bash binary lives in the `runtime` domain and must be removed by hand.
The result is glibc + openssl certs + tzdata + base files and nothing else.

Pipeline: `stack` (list deps) -> `compose` (chisel) -> `script` (oci-builder).

## Versioning

There is no application version for a base image, so the version axis is the
FSDK release. Tags are derived from the pinned junction ref in
`elements/freedesktop-sdk.bst`:

- `:latest` -- rolling
- `:25.08` -- FSDK minor line
- `:25.08.13` -- FSDK point release (treated immutable)

Every image self-declares its base via `io.projectbluefin.fsdk.version` and
`io.projectbluefin.fsdk.ref` labels.

## Build locally

Requires `podman` and [`just`](https://github.com/casey/just). BuildStream runs
inside the FSDK `bst2` container -- nothing to install.

    just validate        # resolve the element graph
    just build           # build + load ghcr.io/projectbluefin/base:latest
    just verify          # assert distroless + certs + tzdata
    just tags            # show derived tags

## License

Apache-2.0.

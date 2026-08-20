---
name: container-standards
version: "1.2"
last_updated: 2026-08-20
id: container-standards
one_line_purpose: Define the build, verification and tagging standard every image must meet.
entry_point: docs/skills/container-standards.md
category: meta
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [standards, verification, tagging, compliance, non-root, security-context]
description: "The Standard of Quality for fsdk-containers: build rules, verification gates, the non-root user contract, and tagging. Use when verifying an image or adding one."
metadata:
  type: policy
---

# Container Standard of Quality

## When to Use
- Adding a new container runtime or application to the suite.
- Verifying whether an existing container meets standard compliance.
- Auditing the tagging and signing configurations.

## When NOT to Use
- Managing machine-images/nspawn containers (see `nspawn-machine-image.md`).

## Core Process

### 1. The FSDK Quality Contract

- **Inheritance, not reinvention:** We never maintain a separate package set. All system libraries (glibc, ssl) inherit FSDK's CVE patching and reproducible builds automatically.
- **Distroless by default:** Except for documented shell-enabled lanes (like `lab-runner`), images must not contain a shell (`bash`, `sh`, `zsh`) or package managers (`apk`, `apt`, `dnf`). Shell-enabled images explicitly pull the staged FSDK shell stack.
- **Minimal footprint:** Images must remain slim. `just verify` enforces per-image **uncompressed** size ceilings (64–512 MiB by image; the `MAX_BYTES` cases in the Justfile). All non-runtime development artifacts, compilers, and test suites must be pruned.
- **Shell-enabled utility contract:** `lab-runner` is an explicit exception for cluster automation. It must ship the complete CLI contract used by Argo templates (`argo`, `just`, and `kubectl`), the image-inspection tool downstream automation verifies published tags with (`skopeo` — review's landing agent runs `skopeo inspect docker://<image>:stable`, issue #164), and the contributor linter suite (`shellcheck`, `hadolint`, and `actionlint`) without relying on a runtime package manager or network bootstrap. It must also ship the standard POSIX/GNU userland beyond coreutils — `which`, `xargs`, `awk`, `ps`, `tar`, `diff`, `patch`, `less`, `file`, and `gzip` — because a shell-enabled image with no package manager gives its consumers no way to recover from a missing basic tool, and each gap gets worked around downstream instead. `gzip` in particular is not optional alongside `tar`: GNU tar execs `gzip` as a child process for `.tar.gz` streams, so `tar` being present is not sufficient to read a gzip-compressed archive — shipping `tar` without `gzip` fails `tar -xzf` with "Cannot exec: No such file or directory" even though `tar --version` works fine. It must additionally ship `bubblewrap` (`bwrap`): projectbluefin/review's worktree-guard wrapper sandboxes agent commands with `bwrap --ro-bind / / true` when bwrap is available and silently degrades to worktree-only isolation when it is not (issue #109). Rootless nested sandboxing needs unprivileged user namespaces, so shipping the binary is not sufficient — `just verify` probes the exact command inside the container. These come from FSDK `components/*` (`findutils`, `procps`, `gawk`, `tar`, `diffutils`, `patch`, `less`, `file`, `which`, `gzip`, `bubblewrap`), dedicated elements (`lab-runner/*.bst`), and the catalog's own `skopeo/skopeo-stack.bst` (depend on that stack rather than relisting its components, so the bundle is maintained in exactly one place). Do not satisfy any of this with a Containerfile overlay or a hand-written shim in a derived image.

---

## 2. The Verification Gates

`just verify` is the merge contract. Every OCI image must pass a per-image size
ceiling, the gates below, and — for images that ship a real binary — a smoke
test that executes it (`base`/`static` get their `/usr/bin/true` smoke only in
the post-publish `publish-smoke` job).

Distroless images (all except `lab-runner`):

| Gate | Validation | Why It Matters |
| --- | --- | --- |
| **Gate 1** | No shell present | The distroless guarantee: no `sh`/`bash` in the rootfs. |
| **Gate 2** | CA certificate bundle | HTTPS works out of the box. |
| **Gate 3** | Timezone data | Keeps `usr/share/zoneinfo/UTC` so runtimes do not crash. |
| **Gate 4** | Sanitizer/fortran bloat removed | No `libasan`, `libtsan`, `libgfortran` and friends. |
| **Gate 5** | Locale/build-tool bloat removed | No `locale-archive`, charmaps, `ldconfig`, `pcre2` tooling. |

`lab-runner` is the documented shell-enabled exception and is verified against an
inverted contract instead — bash present, the `argo`/`just`/`kubectl`/`skopeo` CLI
contract present (including a functional, network-free `skopeo inspect` of a local
OCI layout), the standard POSIX/GNU userland present (including `gzip` and `bwrap`,
both functionally probed), and the full terminfo database present.

Terminfo is deliberately **kept** in every base-derived image: it is ~0.5 MB
compressed, and removing it produced real colour and rendering bugs downstream.
(`static` ships certs + tzdata only and carries no ncurses.)

### The non-root contract (decided in #120, not yet implemented)

**Default `65532:65532`, numeric, with a matching `/etc/passwd` entry.** Both halves are
required — see below for why the second one is not optional.

The UID must be **numeric** in the image config, never a name. The kubelet only supports
numeric users for `runAsNonRoot` (`kuberuntime_container.go:354` — *"Non-root verification only
supports numeric user"*; `security_context_others.go:48-53` returns a hard error otherwise). A
named user is rejected outright, not degraded. `65532` matches `gcr.io/distroless`'s `nonroot`.

**A bare UID is not enough — ship the passwd entry too.** Running as a UID with no
`/etc/passwd` record, `buildah` fails before it starts:

```
level=error msg="unable to resolve HOME directory: user: unknown userid 65532"
```

Python is quieter but still broken — `getpass.getuser()` raises `OSError`, `pwd.getpwuid()`
raises `KeyError`, and `os.path.expanduser("~")` silently returns `/`. Anything calling
`getpwuid` is at risk. Once the entry is present, the image can run non-root.

`/home/nonroot` is root-owned and **not writable**: the BST sandbox cannot `chown` to a UID
(`EINVAL`). This is deliberate — a workload needing a writable home mounts an `emptyDir`. Do not
try to defeat the sandbox constraint.

Assert the gate by **inspecting the image config**, not at runtime:

```console
$ podman image inspect --format '{{.Config.User}}' "$REF"   # numeric uid:gid, uid != 0
```

A runtime `id -u` is impossible — there is no shell to run it in.

> [!WARNING]
> **`podman run --passwd` defaults to `true`** and invents a `/etc/passwd` entry for any
> `--user` UID that is missing, complete with a fabricated `pw_gecos='container user'`.
> Kubernetes runtimes do **not** do this. A smoke test written as plain `podman run --user ...`
> therefore passes on an image that cannot start in-cluster. **Always pass `--passwd=false`
> when testing non-root behaviour**, or you are testing podman rather than the image.

---

## 3. Automated Dependency Updates (GitOps / Renovate)

GitHub Actions are auto-updated via Renovate's built-in `github-actions` manager.

BuildStream source updates must be atomic. `renovate.json` has a single
`custom.regex` manager that reads `# renovate: datasource=... depName=...`
annotations in `.bst` files and the Justfile. For `git_repo` sources the
annotation sits on `track:` (`datasource=github-tags`); Renovate bumps the
tag, and the `refresh-bst-refs.yml` workflow then re-runs `bst source track`
on the PR branch to write the matching commit `ref:`:
  ```yaml
  # renovate: datasource=github-tags depName=containers/buildah
  track: v1.45.0
  ref: <matching commit SHA>   # refreshed by CI, never hand-edited
  ```
Archive and remote binary sources pin a sha256 `ref:` and are refreshed by
the same workflow. Do not restore the old generic regex manager: a release
version alone cannot identify or verify the exact archive artifact, which is
why the broad matcher was removed for [issue #50](https://github.com/projectbluefin/fsdk-containers/issues/50).

---

## 4. SRE-Reliable Tagging Strategy

Every OCI image is published with tags derived dynamically from the pinned FSDK release in `freedesktop-sdk.bst`:

There is deliberately no `:latest`. A mutable rolling alias lets a consumer
deploy an unpinned image and have it change underneath them with no signal, so
the minor line below is the most permissive tag published.

1. **`:25.08` / `:26.08` (Stable Minor Line)**  
   e.g. `:25.08`. Tracks patch updates to that minor line. Balances security patches with high stability.
2. **`:25.08.14` / `:26.08beta.1` (Immutable Point / Pre-release Tag)**  
   e.g. `:25.08.14` or `:26.08beta.1`. Point releases and upstream pre-releases/betas/RCs are tagged automatically, ensuring every upstream development and beta line is published. **Recommended for SRE production environments to guarantee 100% reproducible deployments.**

### Dynamic Metadata Labeling
Every image must be self-declaring and embed OCI labels for easy auditing by SRE cluster checkers:
- `org.opencontainers.image.title`
- `org.opencontainers.image.description`
- `org.opencontainers.image.documentation`
- `org.opencontainers.image.source` / `org.opencontainers.image.url`
- `org.opencontainers.image.vendor` / `org.opencontainers.image.licenses`
- `org.opencontainers.image.version` (FSDK version)
- `org.opencontainers.image.revision` (Git commit SHA)
- `org.opencontainers.image.created` (Creation timestamp)
- `io.projectbluefin.fsdk.version`
- `io.projectbluefin.fsdk.ref`

The same set must also reach the **image index** as annotations: GHCR's
package page and ArtifactHub read multi-arch metadata from index annotations,
not from the child manifests' config labels. The manifest job in
`.github/workflows/oci-images.yml` harvests the config labels and re-applies
them with `docker buildx imagetools create --annotation index:...` (runner
podman 4.9 has no index-annotation support; see
[`ci-tooling/references/build-and-manifest-notes.md`](ci-tooling/references/build-and-manifest-notes.md)).

The index annotation `org.opencontainers.image.ref.name` is set in each
`elements/oci/*.bst` to `ghcr.io/projectbluefin/<name>:%{fsdk-version}`, i.e.
the immutable point-release tag, substituted from the pinned FSDK ref. It must
never be a hardcoded tag (and never `:latest`, which is no longer published).

---

## Red Flags
- Version pins in `.bst` files whose `ref` (SHA-256) does not match the corresponding source artifact.
- Including a shell (`/usr/bin/bash` or similar) in a distroless-tier image.
- Static binaries compiled manually without disabling default binary stripping (`strip-binaries: ""`).
- A shell-enabled runner image that omits a command referenced by a workflow template; verify the runner's CLI contract whenever a workflow adds a new executable dependency.
- Images published to GHCR without point-release tagging.
- A non-root image config using a *named* user — the kubelet cannot verify it and rejects the pod.
- A numeric `User` set without a matching `/etc/passwd` entry — `buildah` and anything calling `getpwuid` break at startup.
- Any `podman run --user ...` test without `--passwd=false` — podman fabricates the missing identity and the test lies.

---

## Verification
- [ ] Element validates successfully (`just validate` exits with 0).
- [ ] Image builds and compiles cleanly (`just build`).
- [ ] Verification test suite passes all image-specific gates (`just verify`), including the `lab-runner` CLI contract check.
- [ ] Image uncompressed size is under its `MAX_BYTES` ceiling in the `verify` recipe.
- [ ] OCI Labels contain valid Git hashes and FSDK tags.

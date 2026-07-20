---
name: container-standards
description: The Standard of Quality for fsdk-containers. Defines build rules, verification gates, Renovate autoupdating, and SRE-reliable tagging strategy. Use when verifying an image, adding a language runtime, auditing tagging, or ensuring container compliance.
metadata:
  type: standard
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
- **Distroless by default:** Except for documented shell-enabled lanes (like `lab-runner`), images must not contain a shell (`bash`, `sh`, `zsh`) or package managers (`apk`, `apt`, `dnf`).
- **Minimal footprint:** Images must remain slim, targeting a compressed size under ~50MB (and uncompressed under ~150MB). All non-runtime development artifacts, compilers, and test suites must be pruned.
- **Shell-enabled utility contract:** `lab-runner` is an explicit exception for cluster automation. It must ship the complete CLI contract used by Argo templates (`argo`, `just`, and `kubectl`) without relying on a runtime package manager or network bootstrap.

---

## 2. The Four Verification Gates

All OCI images (except explicit exceptions) must pass the `just verify` validation suite containing four automated gates before merge:

| Gate | Validation | Why It Matters |
| --- | --- | --- |
| **Gate 1** | Distroless Assertion | Ensures no shell binaries exist in the rootfs. |
| **Gate 2** | CA Certificate Bundle | Verifies secure HTTPS communication works out-of-the-box. |
| **Gate 3** | Timezone Data (`tzdata`) | Keeps `usr/share/zoneinfo/UTC` so runtimes/Python do not crash. |
| **Gate 4** | Zero-Bloat Recipe | Assures removal of terminfo databases, GCC compiler sanitizers, and Gconv charsets. |

---

## 3. Automated Dependency Updates (GitOps / Renovate)

No version pins may be static or unmonitored. 
- **Renovate regex matching:** Every external binary, package, or track branch must register a `# renovate:` comment above the variable or field:
  ```yaml
  # renovate: datasource=github-releases depName=kubernetes/kubernetes
  kubectl_version: v1.30.2
  ```
- **Automated tracking:** For git repositories, Renovate updates the `track` field, which must then trigger `bst source track <element>` in CI to fetch and pin the exact, secure cryptographic commit `ref:` hash.

---

## 4. SRE-Reliable Tagging Strategy

Every OCI image is published with three tiers of tags derived dynamically from the pinned FSDK release in `freedesktop-sdk.bst`:

1. **`:latest` (Rolling Dev)**  
   Tracks the current rolling FSDK branch builds. Best for dev/testing lanes.
2. **`:25.08` (Stable Minor Line)**  
   e.g. `:25.08`. Tracks patch updates to that minor line. Balances security patches with high stability.
3. **`:25.08.13` (Immutable Pin)**  
   e.g. `:25.08.13`. A point release corresponding to an exact, immutable FSDK release. **Recommended for SRE production environments to guarantee 100% reproducible deployments.**

### Dynamic Metadata Labeling
Every image must be self-declaring and embed OCI labels for easy auditing by SRE cluster checkers:
- `org.opencontainers.image.title`
- `org.opencontainers.image.version` (FSDK version)
- `org.opencontainers.image.revision` (Git commit SHA)
- `org.opencontainers.image.created` (Creation timestamp)
- `io.projectbluefin.fsdk.version`
- `io.projectbluefin.fsdk.ref`

---

## Red Flags
- Any hardcoded version tags in `.bst` files with no corresponding `# renovate:` comment.
- Including a shell (`/usr/bin/bash` or similar) in a distroless-tier image.
- Static binaries compiled manually without disabling default binary stripping (`strip-binaries: ""`).
- A shell-enabled runner image that omits a command referenced by a workflow template; verify the runner's CLI contract whenever a workflow adds a new executable dependency.
- Images published to GHCR without point-release tagging (e.g. only `:latest`).

---

## Verification
- [ ] Element validates successfully (`just validate` exits with 0).
- [ ] Image builds and compiles cleanly (`just build`).
- [ ] Verification test suite passes all image-specific gates (`just verify`), including the `lab-runner` CLI contract check.
- [ ] Image uncompressed size is under ~150MB.
- [ ] OCI Labels contain valid Git hashes and FSDK tags.

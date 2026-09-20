# Upstream Base Audit Matrix

Research output resolving [#114](https://github.com/projectbluefin/fsdk-containers/issues/114).
Parent map: [#113](https://github.com/projectbluefin/fsdk-containers/issues/113).

Evidence gathered from upstream build sources — Dockerfiles, `.ko.yaml`, Gradle build
files and Makefiles — not from documentation or recall.

## Catalog rules applied

From map #113:

- **IN** — the final-stage base is a classic general-purpose distro: Amazon Linux, any
  enterprise Linux (RHEL, UBI, Rocky, Alma, CentOS Stream), Ubuntu, Debian (incl.
  `-slim`), openSUSE/SLES, Fedora, Alpine. These carry a package manager, a shell and
  ambient CVE surface FSDK removes.
- **OUT** — the final-stage base is apko/Chainguard/Wolfi, `gcr.io/distroless/*`, `ko`,
  or `scratch`. No impact to win, and we would regress on size against a ~2MB static image.

Only the **final** stage counts. Most of these projects use multi-stage builds with a fat
builder and a thin runtime; judging by the builder stage gives the wrong answer.

## Matrix

| Target | Final-stage base | Verdict | Source |
| --- | --- | --- | --- |
| cloud-custodian (`cli`, `kube`, `org`, `mailer`, `policystream`) | **Ubuntu 24.04**, `apt` retained, named USER `custodian` | **IN** | [docker/c7n](https://github.com/cloud-custodian/cloud-custodian/blob/main/docker/c7n), [dockerpkg.py](https://github.com/cloud-custodian/cloud-custodian/blob/main/tools/dev/dockerpkg.py) |
| opensearch | AlmaLinux (`dnf` in final stage) | **IN** | [build.gradle](https://github.com/opensearch-project/OpenSearch/blob/main/distribution/docker/build.gradle), [Dockerfile](https://github.com/opensearch-project/OpenSearch/blob/main/distribution/docker/src/docker/Dockerfile) |
| jre (Temurin) | Ubuntu 22.04 | **IN** | [adoptium/containers](https://github.com/adoptium/containers/blob/main/25/jre/ubuntu/jammy/Dockerfile) |
| mariadb | Ubuntu | **IN** | [Dockerfile.template](https://github.com/MariaDB/mariadb-docker/blob/master/Dockerfile.template) |
| node | Debian `buildpack-deps` | **IN** | [docker-node](https://github.com/nodejs/docker-node/blob/main/24/bookworm/Dockerfile) |
| go | Debian `buildpack-deps` | **IN** | [docker-library/golang](https://github.com/docker-library/golang/blob/master/1.25/bookworm/Dockerfile) |
| valkey | Debian `-slim` (Alpine variant also published) | **IN** | [valkey-container](https://github.com/valkey-io/valkey-container/blob/mainline/Dockerfile.template) |
| postgres | Debian `-slim` | **IN** | [docker-library/postgres](https://github.com/docker-library/postgres/blob/master/Dockerfile-debian.template) |
| python | Debian `-slim` | **IN** | [docker-library/python](https://github.com/docker-library/python/blob/master/3.13/slim-trixie/Dockerfile) |
| nginx | Debian `trixie-slim` | **IN** | [docker-nginx](https://github.com/nginx/docker-nginx/blob/master/mainline/debian/Dockerfile) |
| curl | Alpine | **IN** | [curl-container](https://github.com/curl/curl-container/blob/main/Makefile) |
| volcano | Alpine | **IN** | [volcano installer](https://github.com/volcano-sh/volcano/blob/master/installer/dockerfile/controller-manager/Dockerfile) |
| kubestellar-hive | Debian trixie (`node:26-slim`) — *corrected by #124 below; originally recorded as Alpine* | **IN** | [kubestellar/hive](https://github.com/kubestellar/hive/blob/v2/v2/Dockerfile) |
| falco | Chainguard Wolfi — **but `apk` retained in final image** | **EXCEPTION** | [falco Dockerfile](https://github.com/falcosecurity/falco/blob/master/docker/falco/Dockerfile) |
| coredns | `gcr.io/distroless/static-debian12`, USER 65532 | OUT | [coredns](https://github.com/coredns/coredns/blob/master/Dockerfile) |
| argo-workflows (controller) | `gcr.io/distroless/static-debian13`, USER 8737 | OUT | [argo-workflows](https://github.com/argoproj/argo-workflows/blob/main/Dockerfile) |
| argo-workflows (argoexec) | `gcr.io/distroless/static-debian13`; root and UID-8737 targets both published | OUT | same |
| kyverno | `ko` + Wolfi static | OUT | [.ko.yaml](https://github.com/kyverno/kyverno/blob/main/.ko.yaml) |
| opentelemetry-collector (otelcol) | `scratch`, USER 10001 | OUT | [collector-releases](https://github.com/open-telemetry/opentelemetry-collector-releases/tree/main/distributions) |
| opentelemetry-collector (contrib) | `scratch`, USER 10001 | OUT | same |
| kube-vip | `scratch` | OUT | [kube-vip](https://github.com/kube-vip/kube-vip/blob/main/Dockerfile) |
| dragonfly (dfdaemon) | Alpine 3.21.5 (published `latest`, legacy Go client); `debian:bookworm-slim` in the current Rust client — *resolved by #124 below* | **IN** | [dragonflyoss/client](https://github.com/dragonflyoss/client/blob/main/ci/Dockerfile) |
| in-toto | `gcr.io/distroless/base` (`in-toto-golang`) — *resolved by #124 below* | OUT | [in-toto-golang](https://github.com/in-toto/in-toto-golang/blob/master/Dockerfile) |

## Cloud Custodian — added after the initial 20, and the strongest target found

Not in the original brief. Added during review and it outranks everything else.

CNCF project. The final stage is:

```dockerfile
FROM ubuntu:24.04
RUN apt-get --yes update \
      && apt-get --yes install python3 python3-venv adduser --no-install-recommends
RUN adduser --disabled-login --gecos "" custodian
USER custodian
ENTRYPOINT ["/usr/local/bin/custodian"]
```

Why it ranks first:

1. **Ubuntu 24.04 final base** — the fattest tier in the IN rule, with `apt` and a shell
   left in the runtime image.
2. **It is a Python application**, and this repo already ships a working distroless
   `python` image (`elements/oci/python.bst`). The exemplar therefore reuses an existing,
   proven lane instead of inventing one.
3. **`USER custodian` is a named user.** Kubernetes rejects named users under
   `runAsNonRoot` — it cannot verify them (the same failure CoreDNS documented when it
   moved to numeric `65532:65532`). Switching to a numeric UID is a genuine correctness
   improvement, not just a size win. See the user-contract ticket
   [#120](https://github.com/projectbluefin/fsdk-containers/issues/120).
4. **It is five images, not one** — `cli`, `kube`, `org`, `mailer`, `policystream` — all
   generated from a single Python generator, `tools/dev/dockerpkg.py`, onto the same base.

Point 4 is the decisive one for this map. Cloud Custodian has *already solved upstream*
the problem [#118](https://github.com/projectbluefin/fsdk-containers/issues/118) and
[#119](https://github.com/projectbluefin/fsdk-containers/issues/119) are deciding: images
declared as data and generated, rather than hand-written. Building it here yields five
catalog images off one pattern, which demonstrates the marginal-cost collapse directly
rather than by assertion — and upstream's own generator is a reference design for ours.

Recommend Cloud Custodian as the exemplar, displacing OpenSearch.

## The Falco exception

Falco's base is `cgr.dev/chainguard/wolfi-base`, which is OUT by rule. But the final image
then runs `apk add curl ca-certificates jq libstdc++` — leaving a **package manager, a
shell and two extra CLI tools in the runtime layer**.

That is precisely the ambient CVE surface this catalog exists to remove. The rule keys on
*base provenance*; Falco fails on *final-image contents*. Recommend an explicit IN
exception, recorded as an exception rather than by bending the rule.

## The finding that reshapes the catalog

**The CNCF half of the original brief largely evaporated.**

Of the 10 CNCF targets: 5 are OUT (coredns, argo-workflows, kyverno, otel-collector,
kube-vip), 2 are unevidenced (dragonfly, in-toto), and only 3 survive — Volcano,
KubeStellar Hive, and Falco by exception.

The surviving catalog is dominated by the **enterprise runtime / data-engine half**, which
maps largely onto FSDK components that already exist.

Two consequences for the map:

1. "Ingest an upstream Go binary with no FSDK component" is **less central** than assumed
   during charting. It is still required for Volcano, KubeStellar Hive and Falco.
2. The exemplar should be drawn from the **fat-base targets**, where the delta is largest
   and the pattern generalises across the most surviving images.

**Cloud Custodian partially restores the CNCF story** — it is a CNCF project on Ubuntu with
`apt` in the final image, so the catalog is not reduced to language runtimes alone.

## Ranked keep-list

Ranked by upstream base weight crossed with deployment breadth.

1. **Cloud Custodian** — Ubuntu 24.04 + `apt` + named user. CNCF, Python-based (reuses
   this repo's existing lane), and five images from one generator. Recommended exemplar.
2. **OpenSearch** — AlmaLinux + `dnf` + bundled JDK. Largest single-image delta.
3. **Node** — Debian `buildpack-deps`, very fat, enormous pull volume.
4. **JRE (Temurin)** — Ubuntu 22.04; also unlocks OpenSearch.
5. **Go** — Debian `buildpack-deps`.
6. **MariaDB** — Ubuntu.
7. **PostgreSQL** — Debian `-slim`.
8. **Python** — Debian `-slim`. Already built in this repo.
9. **nginx** — Debian `trixie-slim`.
10. **Valkey** — Debian `-slim`.
11. **curl** — Alpine. Already partially present.
12. **Volcano** — Alpine. First target needing the Go ingestion path.
13. **KubeStellar Hive** — Debian trixie (`node:26-slim`), multi-runtime. *(Base corrected by #124.)*
14. **Falco** — by exception; eBPF makes it the most expensive.

## Known gap — closed

The original version of this document stated: *"Uncompressed image sizes were not measured.
The research environment could not pull images. Every size-delta claim in this catalog remains
unverified until someone runs the comparison."* That gap is closed by the **Measured sizes**
section below (compressed sizes, 2026-08-09) and by the #124 extension at the end of this
document (compressed and uncompressed, digest-pinned, 2026-09-20). The paragraph is kept so
the history of the claim is visible.

## Method note

Where a project builds images via `ko`, `apko`, `melange`, Bazel `rules_oci` or GoReleaser
rather than a Dockerfile, that config was read instead — Kyverno's `OUT` verdict comes from
`.ko.yaml`, not a Dockerfile, and would have been missed otherwise.

## Measured sizes

Closes the gap flagged in the original version of this document, where no sizes were
measured. Figures are **compressed registry transfer sizes** for `linux/amd64`, summed from
manifest layer sizes via `skopeo inspect --raw` on 2026-08-09. They are *not* comparable to
the uncompressed local Podman sizes that `just verify` gates on — those run roughly 2-3x
larger. Use one metric or the other consistently; do not mix them.

### Upstream targets

| Target | Upstream image | Compressed |
| --- | --- | --- |
| pytorch | `pytorch/pytorch:latest` | 3490.5 MB |
| opensearch | `opensearchproject/opensearch:latest` | 1084.0 MB |
| node | `node:24-bookworm` | 390.0 MB |
| go | `golang:1.25-bookworm` | 276.3 MB |
| cloud-custodian | `cloudcustodian/c7n:latest` | 162.0 MB |
| postgres | `postgres:latest` | 154.8 MB |
| jre | `eclipse-temurin:25-jre` | 120.2 MB |
| mariadb | `mariadb:latest` | 102.7 MB |
| nginx | `nginx:mainline` | 60.2 MB |
| valkey | `valkey/valkey:latest` | 42.3 MB |
| python | `python:3.13-slim` | 41.0 MB |
| curl | `curlimages/curl:latest` | 10.2 MB |

### Baseline — this repo, and reference bases

| Image | Compressed |
| --- | --- |
| `ghcr.io/projectbluefin/python:latest` | 37.2 MB |
| `ghcr.io/projectbluefin/static:latest` | 15.9 MB |
| `ghcr.io/projectbluefin/base:latest` | **15.8 MB** |
| `ubuntu:24.04` | 28.4 MB |
| `debian:trixie-slim` | 28.4 MB |
| `gcr.io/distroless/base-debian12:nonroot` | 7.8 MB |
| `alpine:latest` | 3.7 MB |
| `gcr.io/distroless/static-debian12:nonroot` | 0.7 MB |

## What the numbers actually say

### 1. The FSDK base beats the distros it replaces

`base` at **15.8 MB** is roughly **45% smaller than `ubuntu:24.04` or `debian:trixie-slim`
(both 28.4 MB)**, while carrying no shell and no package manager. Against a classic-distro
base the substitution is a straight win on every axis at once. This validates the IN rule.

### 2. But the OS-replacement delta is roughly constant, ~13-25 MB

Swapping a distro base for FSDK saves what the distro layer weighed — about 13 MB against
Ubuntu/Debian. **That saving does not scale with image size.** Consequences:

| Upstream size | OS delta | Proportional win |
| --- | --- | --- |
| curl (10 MB) | ~13 MB | dominant |
| python (41 MB) | ~13 MB | large |
| c7n (162 MB) | ~13 MB | ~8% |
| opensearch (1084 MB) | ~13 MB | ~1% |
| pytorch (3490 MB) | ~13 MB | **<0.5%** |

The bulk of a large image is its *payload* — JDK, `site-packages`, CUDA, `node_modules` —
which the SLIM recipe does not touch.

### 3. This is decisive for the AI/ML lane (#124)

On PyTorch the OS delta is **under half a percent**. Any pitch for distroless PyTorch on
size grounds is not supportable by these numbers. If that lane proceeds it must be justified
by shell/package-manager removal and provenance alone — and #124's caveats (proprietary
CUDA, users expecting `kubectl exec`) apply at full force. Treat sceptically.

### 4. The existing `python` image is a warning

`ghcr.io/projectbluefin/python` (37.2 MB) is only **9% smaller** than `python:3.13-slim`
(41.0 MB) — despite a base that is 45% lighter than Debian. Upstream `-slim` variants are
already well optimised. **Do not benchmark against fat `:latest` tags when a `-slim` variant
is what people actually deploy**, or the catalog will publish inflated delta claims.

### 5. It confirms the map's "provenance, not size" decision — with evidence

Map #113 decided value is provenance first and size is a report, not a gate. These numbers
independently support that. The durable, size-independent wins are:

- **No shell** — removes the post-exploitation surface entirely.
- **No package manager** — removes `apt`/`apk`/`dnf` and their CVE stream. Directly relevant
  to Cloud Custodian (`apt` retained) and Falco (`apk` retained).
- **FSDK provenance** — CVE-patched, reproducible, one supply chain across the catalog.

Where size *is* the headline, honesty requires comparing against the `-slim` variant, and
reporting compressed and uncompressed figures separately.

### Method

```
skopeo inspect --raw --override-os linux --override-arch amd64 docker://<ref>
# resolve manifest list -> amd64 digest, then: jq '[.layers[].size] | add'
```

## CORRECTION: the OpenSearch measurement

The "What the numbers actually say" section above claimed the OS-replacement delta is
"roughly constant, ~13-25 MB" and that OpenSearch would gain ~1%. **That was extrapolated
from base-image sizes, never measured, and it is wrong.** The corrected findings follow.
Where the two disagree, this section wins.

### Layer breakdown of the official image

`skopeo inspect --raw --override-os linux --override-arch amd64 docker://opensearchproject/opensearch:latest`

| Layer | Compressed |
| --- | --- |
| AlmaLinux base + `dnf` install layers | **56 MB** |
| OpenSearch payload | **1027 MB** |
| misc | ~1 MB |
| **Total** | **1084 MB** |

The base is 56 MB, not the ~28 MB Ubuntu/Debian figure the generalization assumed.

### Upstream publishes two distributions

Measured via `curl -sfLI` `content-length` on artifacts.opensearch.org:

| Distribution | Size |
| --- | --- |
| `opensearch-2.19.0-linux-x64.tar.gz` (bundle, all plugins) | 919.5 MB |
| `opensearch-min-2.19.0-linux-x64.tar.gz` (min) | **242.6 MB** |
| `opensearch-3.0.0-linux-x64.tar.gz` | 933.3 MB |
| `opensearch-min-3.0.0-linux-x64.tar.gz` | 264.6 MB |

The official image ships the **bundle**. No `-no-jdk` variant is published for either.

### Composition of the min distribution

`tar -xzf` then `du -sm`:

| Component | Uncompressed |
| --- | --- |
| **`jdk/`** | **293 MB (68%)** |
| `modules/` | 86 MB |
| `lib/` | 50 MB |
| config, bin, docs | ~3 MB |
| **Total** | **429 MB** |

Inside `jdk/`: `lib/` 209 MB (of which `lib/modules` 136 MB is the jimage, `server/` 54 MB
is the HotSpot VM, `ct.sym` 11 MB), and `jmods/` 83 MB.

### Lossless strip — measured

Removed **only** build-time artifacts and dev tooling. No runtime module removed, nothing
`jlink`ed, no capability lost:

- `jdk/jmods` (83 MB) — inputs to `jlink`, never used at runtime
- `jdk/lib/ct.sym` (11 MB) — `javac` cross-compilation data
- `jdk/include`, `jdk/man`, `jdk/legal`, `jdk/lib/src.zip` — headers and docs
- 27 dev binaries from `jdk/bin`: `javac`, `javadoc`, `javap`, `jshell`, `jdb`, `jdeps`,
  `jdeprscan`, `jlink`, `jmod`, `jpackage`, `jar`, `jarsigner`, `jconsole`, `jfr`, `jinfo`,
  `jmap`, `jps`, `jstack`, `jstat`, `jstatd`, `jcmd`, `jhsdb`, `jrunscript`, `jwebserver`,
  `rmiregistry`, `serialver`. **Kept `java` and `keytool`.**
- Top-level `README.md`, `NOTICE.txt`, `LICENSE.txt`

| | Uncompressed | gzip | zstd-19 |
| --- | --- | --- | --- |
| min distribution | 429 MB | 243.0 MB | 208.6 MB |
| after lossless strip | **334 MB** | **158.6 MB** | **128.0 MB** |
| reduction | **-22%** | **-35%** | **-39%** |

Smoke test after stripping: `./bin/opensearch --version` -> `Version: 2.19.0 … JVM: 21.0.6`.

Note the compressed reduction (-35% to -39%) exceeds the uncompressed one (-22%): the
removed artifacts (`jmods`, `ct.sym`, `src.zip`) are archives that compress poorly, so they
weigh proportionally more in the shipped image than on disk. **Always quote the compressed
delta for transfer claims.**

### Rejected: jlink

A `jlink`ed runtime with a hand-picked module set produced 63 MB (vs 293 MB) but **failed at
launch**:

```
java.lang.module.FindException: Module jdk.incubator.vector not found
```

Lucene uses `jdk.incubator.vector` for SIMD, which underpins vector search — OpenSearch's
headline feature. Adding it back plus `jdk.management.agent`, `jdk.naming.dns`, `java.rmi`
and `jdk.net` got `--version` passing at 63 MB, but the failure demonstrates the hazard:
**a hand-picked module set silently removes capabilities the application needs, and the
failure mode is a runtime exception, not a build error.**

This is re-architecting upstream, not packaging it. **Out of scope for this project.** We
remove shells, package managers, docs, build-time artifacts and duplicate bloat. We do not
redesign the applications we package. Documented so nobody retries it.

### Corrected projection

| | |
| --- | --- |
| Official image | 1084 MB |
| FSDK base (measured) | ~16 MB |
| min distribution + lossless strip (gzip) | ~158.6 MB |
| **Projected total** | **~175 MB (~84% reduction)** |

**Contingent on** min-plus-required-plugins being an acceptable product decision. The
required plugin set has **not** been verified — that is scoping work for the exemplar build
(#123), and the projection must not be published until it is.

### The generalizable rule

On fat images the win is **distribution choice** and **build-time-artifact removal**, not the
base layer. The base swap is worth ~40 MB here; the packaging work is worth ~750 MB.

For the JVM lane specifically: prefer upstream's `-min` distribution, then strip `jmods`,
`ct.sym`, `src.zip`, headers and JDK dev tooling. This is a repeatable recipe and should
become a `docs/skills/` JVM lane document.

### Method

```sh
skopeo inspect --raw --override-os linux --override-arch amd64 docker://<ref> \
  | jq '[.layers[].size] | add'
curl -sfLI <artifact-url> | grep -i content-length
tar -xzf opensearch-min-2.19.0-linux-x64.tar.gz && du -sm *
# strip build-time artifacts + dev tooling, re-measure, smoke test
tar -c <dir> | zstd -19 -T0 -c | wc -c
```

## AI/ML and CNCF-Adjacent Extension (#124)

Resolves [#124](https://github.com/projectbluefin/fsdk-containers/issues/124). Extends the
catalog audit to AI/ML serving, training/orchestration, vector databases, CNCF-adjacent
infrastructure with fat bases, and the `nvidia/cuda` base layers, and answers the question
#124 asked: does the distroless value proposition survive for GPU/ML images?

Every figure in this section was measured on **2026-09-20** against the digest-pinned
`linux/amd64` manifests listed in the [Method](#method-124) block at the end. Moving tags
(`:latest`) appear in the tables only as the *name the digest was resolved from*; the digest
is what was measured. Sizes are compressed registry transfer sizes in MiB (labelled "MB"
elsewhere in this document; the #114 tables use the same unit — `pytorch/pytorch` at the same
digest sums to 3,490.5 in both), except where a row says "uncompressed".

This section also corrects four rows in the #114 half of this document in place (KubeStellar
Hive base, Dragonfly and in-toto `HOLD` verdicts, and the "Known gap" note) rather than
leaving both answers standing. Where this section and #114 prose still disagree, this
section wins.

### Resolution of #114 unmeasured and HOLD targets

1. **Volcano** (`volcanosh/vc-controller-manager`, `vc-scheduler`, `vc-webhook-manager`)
   - **Final-stage base**: Alpine 3.24.1 (`alpine-minirootfs-3.24.1`, 3.7 MiB layer). No `USER`.
   - **Compressed**: controller-manager **28.1** (3.7 + 24.4), scheduler **32.6** (3.7 + 29.0),
     webhook-manager **46.7** (3.7 + 20.2 + 22.9, plus an empty layer).
   - **Verdict**: **IN**. Shell and `apk` in the final stage, small static Go payloads.

2. **Falco** (`falcosecurity/falco`)
   - **Final-stage base**: `falco` is `cgr.dev/chainguard/wolfi-base` with
     `apk add curl ca-certificates jq libstdc++` in the final stage
     ([docker/falco/Dockerfile](https://github.com/falcosecurity/falco/blob/master/docker/falco/Dockerfile)).
     `falco-no-driver` is **not** Wolfi: its image history is a Debian `rootfs.tar.xz` followed
     by `apt-get install ca-certificates curl jq libelf1`.
   - **Compressed**: `falco` **47.9** (14 layers, `USER 0`), `falco-no-driver` **71.5** (3 layers, root).
   - **Verdict**: **EXCEPTION (IN)**, unchanged from #114. Package manager, shell and CLI
     tooling in the final stage of both variants; eBPF probe buildable, kmod deferred per #113.

3. **KubeStellar Hive** (`ghcr.io/kubestellar/hive`)
   - **Final-stage base**: `node:26-slim` (Debian trixie, 28.4 MiB base layer) — read from
     `v2/Dockerfile` line 43 and confirmed by the image history (`debian.sh … 'trixie'`).
     **The #114 matrix said Alpine; that row is corrected.**
   - **Compressed**: **1,496.0** across 68 layers. No `USER` in the image config, so the
     container starts as root; the Dockerfile creates a `dev` user (uid 1001) and ships
     `su-exec` for the entrypoint to drop to it.
   - **Verdict**: **IN**. Node, Python virtualenvs, Go toolchain, tmux and git in one image;
     large CVE surface.

4. **Dragonfly** (`dragonflyoss/dfdaemon`)
   - **Measured `latest` digest**: Alpine 3.21.5 rootfs, 4 layers (3.5 + 0 + 41.3 + 4.1),
     **48.9**, no `USER`. The entrypoint is `/opt/dragonfly/bin/dfget daemon`: this is the
     legacy Go client from Dragonfly2, and its Dockerfile no longer exists at Dragonfly2
     `HEAD` (`build/images/` now holds only `base`, `manager` and `scheduler`).
   - **Current upstream source**: the Rust client at
     [dragonflyoss/client `ci/Dockerfile`](https://github.com/dragonflyoss/client/blob/main/ci/Dockerfile),
     whose final stage is `debian:bookworm-slim` (the `alpine:3.23.4` stage in that file is a
     health-check helper, not the runtime). Published tag and current source disagree on the
     distro; the verdict is the same either way.
   - **Verdict**: **IN** (resolved from `HOLD`). Shell and package manager in every variant.

5. **in-toto** (`in-toto/in-toto-golang`)
   - **Build source**: [in-toto-golang Dockerfile](https://github.com/in-toto/in-toto-golang/blob/master/Dockerfile),
     final stage `FROM gcr.io/distroless/base`.
   - **Verdict**: **OUT** (resolved from `HOLD`). Already distroless; no packaging delta to win.

---

### AI/ML and CNCF-adjacent matrix

Final-stage base and package manager come from the upstream build source in the last column,
cross-checked against the image config history (rootfs `ADD`, `org.opencontainers.image.version`
label for Ubuntu). `USER` is the image config's `User` field as published; blank means root.

| Target | Ref measured (see Method for digest) | Final-Stage Base | Shell / Pkg Mgr | USER | Compressed (MiB) | Verdict | Upstream Build Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Inference / Serving** | | | | | | | |
| vllm | `vllm/vllm-openai:latest` (v0.29.0) | `nvidia/cuda:*-base-ubuntu24.04` (Ubuntu 24.04) | `bash`, `apt` | root | 8,272.3 | **CONDITIONAL** | [vllm/docker/Dockerfile](https://github.com/vllm-project/vllm/blob/main/docker/Dockerfile) |
| triton-inference-server | `nvcr.io/nvidia/tritonserver:24.08-py3` | Ubuntu 22.04 | `bash`, `apt` | root | 8,735.8 | **CONDITIONAL** | [triton Dockerfile](https://github.com/triton-inference-server/server/blob/main/Dockerfile) |
| kserve (controller) | `kserve/kserve-controller:latest` | `gcr.io/distroless/static:nonroot` | none | `65532` | 41.8 | **OUT** | [kserve/Dockerfile](https://github.com/kserve/kserve/blob/master/Dockerfile) |
| kserve (storage-init) | `kserve/storage-initializer:latest` | `python:3.11-slim-bookworm` | `sh`, `apt` | `1000` | 92.0 | **IN** | [storage-initializer.Dockerfile](https://github.com/kserve/kserve/blob/master/python/storage-initializer.Dockerfile) |
| torchserve (cpu) | `pytorch/torchserve:latest-cpu` | Ubuntu 20.04 | `bash`, `apt` | `model-server` | 669.4 | **IN** | [serve/docker/Dockerfile](https://github.com/pytorch/serve/blob/master/docker/Dockerfile) |
| tgi (text-gen-inf) | `ghcr.io/huggingface/text-generation-inference:latest` | Ubuntu 22.04 | `bash`, `apt` | root | 8,825.6 | **CONDITIONAL** | [tgi/Dockerfile](https://github.com/huggingface/text-generation-inference/blob/main/Dockerfile) |
| ollama | `ollama/ollama:latest` | Ubuntu 24.04 | `bash`, `apt` | root | 3,538.5 | **CONDITIONAL** | [ollama/Dockerfile](https://github.com/ollama/ollama/blob/main/Dockerfile) |
| seldon-core-operator | `seldonio/seldon-core-operator:1.18.2` | UBI 9 minimal | `sh`, `microdnf` | `8888` | 161.4 | **IN** | [seldon-core](https://github.com/SeldonIO/seldon-core) |
| **Training / Orchestration** | | | | | | | |
| ray (cpu) | `rayproject/ray:2.35.0-cpu` | Ubuntu 22.04 + Conda | `bash`, `apt`, `conda` | `1000` | 798.2 | **IN** | [ray/docker/ray/Dockerfile](https://github.com/ray-project/ray/blob/master/docker/ray/Dockerfile) |
| ray (gpu) | `rayproject/ray:2.35.0-cu121` | `nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04` + Conda | `bash`, `apt`, `conda` | `1000` | 5,983.8 | **OUT OF SCOPE** | same |
| kubeflow (training-op) | `kubeflow/training-operator:latest` | distroless static (Bazel/Debian 13 build; current source: `gcr.io/distroless/static:nonroot`) | none | `0` on the measured `latest` (built 2026-08-18) | 31.1 | **OUT** | [trainer/cmd/trainer-controller-manager/Dockerfile](https://github.com/kubeflow/trainer/blob/master/cmd/trainer-controller-manager/Dockerfile) |
| volcano (controller) | `volcanosh/vc-controller-manager:latest` | Alpine 3.24.1 | `sh`, `apk` | root | 28.1 | **IN** | [volcano installer](https://github.com/volcano-sh/volcano/blob/master/installer/dockerfile/controller-manager/Dockerfile) |
| volcano (scheduler) | `volcanosh/vc-scheduler:latest` | Alpine 3.24.1 | `sh`, `apk` | root | 32.6 | **IN** | [volcano installer](https://github.com/volcano-sh/volcano/blob/master/installer/dockerfile/scheduler/Dockerfile) |
| argo-workflows | `argoproj/workflow-controller:latest` | `gcr.io/distroless/static-debian13` | none | `8737` | 43.3 | **OUT** | [argo-workflows/Dockerfile](https://github.com/argoproj/argo-workflows/blob/main/Dockerfile) |
| **Vector & Data Engines** | | | | | | | |
| milvus | `milvusdb/milvus:latest` | Ubuntu 22.04 | `bash`, `apt` | `milvus:milvus` | 568.9 | **IN** | [milvus ubuntu22.04/Dockerfile](https://github.com/milvus-io/milvus/blob/master/build/docker/milvus/ubuntu22.04/Dockerfile) |
| qdrant | `qdrant/qdrant:latest` | `debian:trixie-slim` | `sh`, `apt` | `0:0` | 70.7 | **IN** | [qdrant/Dockerfile](https://github.com/qdrant/qdrant/blob/master/Dockerfile) |
| weaviate | `semitechnologies/weaviate:latest` | Alpine 3.24.2 | `sh`, `apk` | root | 85.2 | **IN** | [weaviate/Dockerfile](https://github.com/weaviate/weaviate/blob/master/Dockerfile) |
| minio | `quay.io/minio/minio:latest` (Docker Hub `minio/minio:latest` returned "access denied" on 2026-09-20) | `ubi9/ubi-micro` | `sh` entrypoint | root | 59.4 | **IN** | [minio/Dockerfile](https://github.com/minio/minio/blob/master/Dockerfile) |
| **CNCF-Adjacent Infra with Fat Bases** | | | | | | | |
| airflow | `apache/airflow:2.10.0-python3.11` | `python:3.11-slim-bookworm` | `bash`, `apt` | `50000` | 382.9 | **IN** | [airflow/Dockerfile](https://github.com/apache/airflow/blob/main/Dockerfile) |
| spark (core) | `apache/spark:latest` | Ubuntu 22.04 (OpenJDK 17) | `bash`, `apt` | `spark` | 765.6 | **IN** | [spark Dockerfile](https://github.com/apache/spark/blob/master/resource-managers/kubernetes/docker/src/main/dockerfiles/spark/Dockerfile) |
| spark-py | `apache/spark-py:latest` | Ubuntu 22.04 (OpenJDK + Python) | `bash`, `apt` | `185` | 525.1 | **IN** | same |
| prometheus | `prom/prometheus:latest` | BusyBox 1.38.0 (uclibc) / Buildroot | `sh` (busybox) | `nobody` | 104.3 | **IN** | [prometheus/Dockerfile](https://github.com/prometheus/prometheus/blob/main/Dockerfile) |
| grafana | `grafana/grafana:latest` | Alpine 3.24.1 | `sh`, `apk` | `472` | 453.7 | **IN** | [grafana/Dockerfile](https://github.com/grafana/grafana/blob/main/Dockerfile) |
| etcd | `quay.io/coreos/etcd:v3.5.15` | `gcr.io/distroless/static-debian12` | none | `0` | 20.3 | **OUT** | [etcd/Dockerfile](https://github.com/etcd-io/etcd/blob/main/Dockerfile) |
| vault | `hashicorp/vault:latest` | Alpine 3.24.1 (the Dockerfile's `default` target; a separate `ubi` target on `ubi10/ubi-minimal` exists but is not what `latest` ships) | `sh`, `apk` | `vault` | 183.0 | **IN** | [vault/Dockerfile](https://github.com/hashicorp/vault/blob/main/Dockerfile) |
| harbor (core) | `goharbor/harbor-core:v2.12.0` | Photon OS 5.0 | `sh`, `tdnf` | `harbor` | 59.5 | **IN** | [harbor core/Dockerfile](https://github.com/goharbor/harbor/blob/main/make/photon/core/Dockerfile) |
| trivy | `aquasec/trivy:latest` | Alpine 3.24.1 | `sh`, `apk` | root | 58.3 | **IN** | [trivy/Dockerfile](https://github.com/aquasecurity/trivy/blob/main/Dockerfile) |
| keycloak | `quay.io/keycloak/keycloak:latest` | `ubi9/ubi-micro` | `sh` | `1000` | 255.5 | **IN** | [keycloak quarkus/container/Dockerfile](https://github.com/keycloak/keycloak/blob/main/quarkus/container/Dockerfile) |
| elasticsearch | `docker.elastic.co/elasticsearch/elasticsearch:8.15.0` | Ubuntu 20.04 (bundled JDK) | `bash`, `apt` | `1000:0` | 638.1 | **IN** | [elasticsearch/distribution/docker](https://github.com/elastic/elasticsearch/tree/main/distribution/docker) |
| logstash | `docker.elastic.co/logstash/logstash:8.15.0` | Ubuntu 20.04 (OpenJDK + JRuby) | `bash`, `apt` | `1000` | 498.3 | **IN** | [logstash/docker](https://github.com/elastic/logstash/tree/main/docker) |
| **Base Layers (`nvidia/cuda`)** | | | | | | | |
| cuda (base) | `nvidia/cuda:12.4.1-base-ubuntu22.04` | Ubuntu 22.04 | `bash`, `apt` | root | 87.5 | reference | — |
| cuda (runtime) | `nvidia/cuda:12.4.1-runtime-ubuntu22.04` | Ubuntu 22.04 | `bash`, `apt` | root | 1,398.2 | reference | — |
| cuda (devel) | `nvidia/cuda:12.4.1-devel-ubuntu22.04` | Ubuntu 22.04 | `bash`, `apt` | root | 3,921.9 | reference | — |

Rows that changed when the first draft of this section was re-measured by digest, listed so
the drift is visible: `milvus:latest` 1,080.6 → 568.9 (the tag moved, which is exactly why a
moving tag is not evidence); `hive:latest` 1,559.9 → 1,496.0 (same); `vault` is Alpine, not
"UBI minimal / Alpine" (the draft read the Dockerfile's `ubi` target, which `latest` does not
ship); `torchserve` is Ubuntu 20.04, not 22.04; `spark`/`spark-py` are 22.04, not 24.04;
`elasticsearch`/`logstash` 8.15.0 are 20.04, not 24.04; `seldon-core-operator` is UBI 9, not
UBI 8; `harbor-core` runs as `harbor`, not `10000`; `falco-no-driver` is Debian, not Wolfi.
Every other row re-measured to the same figure or within 0.1 MiB.

---

### Anatomy of `pytorch/pytorch` and what a lossless strip recovers

#124 withdrew the unmeasured "<0.5%" claim and asked for the #114 method to be applied.
`pytorch/pytorch:latest` resolved to the same digest #114 measured on 2026-08-09
(`sha256:11691e03…`, PyTorch 2.2.1, CUDA 12.1.1, Ubuntu 22.04.3), so the two halves of this
document measure the same bytes.

#### Layer breakdown

| Layer | Digest | Compressed (MiB) | Uncompressed (MiB) | Content (from image history) |
| --- | --- | --- | --- | --- |
| 0 | `sha256:d66d6a6a368713979f9d00fad193991ae1af18b8efd3abf4d70ade192807c1bd` | 29.04 | 76.7 | Ubuntu 22.04.3 rootfs |
| 1 | `sha256:3ad96c6a423ac845ca1c88befd37f33e5cee0f9c46f6a8c8e73004e5420b19e9` | 6.90 | 26.3 | `apt-get install ca-certificates libjpeg-dev libpng-dev` — the `-dev` packages pull in `libc6-dev`: 12.2 MiB of static `.a` and 8.4 MiB of headers |
| 2 | `sha256:3d552c93e873f61562c7bc8d1e0a9436c890cb44d1a9c97c9a69b864dfb91277` | 3,454.54 | 7,148.2 | `COPY /opt/conda /opt/conda` — the whole Python/PyTorch/CUDA payload |
| 3 | `sha256:4f4fb700ef54461cfa02571ae0db9a0dc1e0cdb5577484a6d75e68dc38e8acc1` | 0.0 (32 B) | — | the conditional `apt install gcc` step; `TRITON_VERSION` was empty, so **gcc is not in this image** |
| 4 | `sha256:42a8919f2ed9b95dfec4eeccf36b869098966254946e137778fbe04025efa338` | 0.0 (99 B) | — | `WORKDIR /workspace` |
| **Total** | | **3,490.48** | | reported as 3,490.5 here and in #114 |

The first draft of this table listed layers 0–2 in decimal megabytes (30.5 / 7.2 / 3,622.3)
under a total in MiB, which is why the column summed to 3,660 against a 3,490.5 total. The
layer sizes above are in MiB and sum to the total. Two consequences for the analysis: the OS
base is 29.0 MiB compressed, **0.8%** of the image; and the "apt and gcc in the final stage"
premise in #124 is half right at this digest — `apt` is there, `gcc` is not.

#### Composition of the payload (Layer 2)

Layer 2 holds **46,321 regular files** (plus 8,262 directories and 41,608 hard/symlinks)
totalling **7,148.2 MiB** uncompressed. Every regular file was assigned to exactly one of the
categories below by a streaming pass over the gzip'd tar (no extraction; the script is in the
Method block), so the rows are disjoint and sum to the total. Percentages are rounded to one
decimal and therefore sum to 100.1.

| Category (first matching rule wins) | Files | Uncompressed (MiB) | % of payload | Strip? |
| --- | --- | --- | --- | --- |
| `opt/conda/lib/*.so*` — CUDA-family 1,974.9 (`libcublasLt` 484.2, `libcusolver` 290.4, `libcusparse` 243.4, `libcusolverMg` 185.3, `libcufft` 183.8, …), Intel MKL 762.2, other 246.8 | 194 | 2,983.9 | 41.7% | no — runtime |
| `site-packages/torch/lib/*.so*` — `libtorch_cuda.so` 1,028.9 + `libtorch_cuda_linalg` 80.8, `libcudnn_*` 1,114.6, `libtorch_cpu.so` 273.6, rest | 19 | 2,562.7 | 35.9% | no — runtime |
| `opt/conda/pkgs/` — conda package cache. **Unpacked** package trees, not tarballs (0.3 MiB of `.tar.bz2`/`.conda`); 378.3 of it is a second copy of `triton/_C/libtriton.so` | 12,837 | 570.6 | 8.0% | **yes** |
| other `.so` (Triton JIT, Python extension modules, misc) | 157 | 460.6 | 6.4% | no — runtime |
| other files (configs, tzdata, conda env state, licences) | 2,673 | 125.9 | 1.8% | no |
| Python sources (`.py`, `.pyi`) | 8,904 | 97.0 | 1.4% | no — runtime |
| `opt/conda/bin/` — `python3.10` 16.4 (runtime); build tooling 66.3 (CMake suite `cmake`/`ctest`/`cpack`/`ccmake` 47.6, `x86_64-conda-linux-gnu-ld`, pcre2 test binaries, `bsdtar`/`bsdcpio`, codec CLIs); 4.2 misc | 195 | 86.8 | 1.2% | **66.3 yes** |
| static archives `*.a` (`libculibos.a`, `libopenblas.a`, …) | 56 | 82.8 | 1.2% | **yes** |
| bytecode (`__pycache__`, `.pyc`) | 7,021 | 74.8 | 1.0% | **yes** (regenerated on import) |
| headers (`include/`, `*.h`, `*.cuh`, `*.hpp`) | 10,122 | 48.1 | 0.7% | **yes** |
| bundled tests (`test/`, `tests/`, `test_*.py`, `*_test.py`) | 3,686 | 43.3 | 0.6% | **yes** |
| docs and man pages | 457 | 11.7 | 0.2% | **yes** |
| **Total** | **46,321** | **7,148.2** | 100.1% (rounding) | |

#### What a lossless strip recovers — measured, not projected

The strippable rows were re-packed into their own tar and gzip'd (level 6, the registry's
format) to measure the compressed bytes they account for, instead of guessing a ratio:

| | Uncompressed (MiB) | Compressed (MiB) |
| --- | --- | --- |
| `opt/conda/pkgs/` cache | 570.6 | |
| static archives | 82.8 | |
| bytecode cache | 74.8 | |
| build tooling in `opt/conda/bin` | 66.3 | |
| headers | 48.1 | |
| bundled tests | 43.3 | |
| docs and man pages | 11.7 | |
| **Layer 2 strip total** | **897.6 (12.6% of payload)** | **292.1 (8.4% of the 3,490.5 image)** |
| Layer 1 `libc6-dev` static archives and headers (separate layer, not re-packed) | 20.6 | small |

So the honest headline is **~290 MiB compressed, ~8%** — not the "~450–500 MB (~14–15%)" the
first draft projected. The strippable content compresses better than the layer average
(3.1:1 against 2.1:1) because it is dominated by text and by one duplicate `.so`, and the
first draft assumed the layer-average ratio.

#### The comparison with OpenSearch

| Metric | OpenSearch (#114) | PyTorch (#124) |
| --- | --- | --- |
| Upstream image, compressed | 1,084 MiB | 3,490.5 MiB |
| Non-runtime payload fraction (uncompressed) | **68%** (JDK build tools, jmods, plugins) | **12.6%** (package cache, tests, static libs, headers, build tooling) |
| Upstream minimal distribution available? | yes (`-min` tarball) | no |
| Core runtime payload compressible? | high (Java bytecode, text) | low (dense compiled kernels; Layer 2 is 2.1:1) |
| Distroless base + lossless strip | **~84%** (1,084 → 175) | **~8%** (3,490.5 → ~3,200) |

The measurement overturns the unmeasured "<0.5%" claim — 8% is real, and most of it is one
duplicated 378 MiB `libtriton.so` sitting in a package cache — but it does not repeat the
OpenSearch result. What remains is **~3,200 MiB compressed of compiled CUDA, cuDNN, MKL and
PyTorch kernels**, and none of it can be removed without pruning functionality, which #124
puts out of scope.

---

### The hard question: does the distroless value proposition survive for GPU/ML?

**No for training and development; conditionally yes for headless inference serving.**
Measured against the three risks #124 named:

#### 1. The provenance trap

FSDK's thesis is source-built, reproducible provenance (#113, #115). At this digest the
proprietary redistributables in the payload are: CUDA-family shared objects in `opt/conda/lib`
**1,974.9 MiB**, cuDNN in `torch/lib` **1,114.6 MiB** — together **3,089.5 MiB uncompressed,
43% of the payload** — plus Intel MKL **762.2 MiB** (54% with MKL). FSDK cannot build any of
it from source. `libtorch_cuda.so` (1,109.7 MiB with `_linalg`) is open-source PyTorch but
needs `nvcc` to compile. Prebuilt binary ingestion was rejected for Go targets in #115; here
the prebuilt blob is more than half the container. An "FSDK PyTorch" would be a ~30 MiB FSDK
base carrying ~3 GB of unverifiable vendor binaries.

#### 2. The interactive shell contract

Training and development are interactive: `kubectl exec -it … -- bash` to inspect a hung
worker, check a checkpoint, or run `nvidia-smi` is standard practice in Kubeflow, Ray Train
and Slurm-on-Kubernetes clusters. Removing `/bin/sh`, `bash` and coreutils makes a training
pod unusable for its audience unless a debug sidecar is always available. Headless serving
runtimes (vLLM, Triton, TGI, KServe's storage initializer) run one HTTP/gRPC daemon as PID 1
behind an API gateway and do not need a shell; removing it there closes a real
post-exploitation path (model-weight deserialisation RCEs are the current example).

#### 3. Vendored native libraries in `site-packages`

The mass is not in `/usr/lib`. `torch/lib` alone is 2,562.7 MiB and `opt/conda/lib` 2,983.9
MiB — inside `/opt/conda`, where the OS-level SLIM recipe (`rm -rf /usr/share/man
/var/lib/apt …`) never reaches. Replacing the Ubuntu base saves 29.0 MiB compressed
(**0.8%**); the packaging-level strip above saves 292.1 MiB (**8.4%**); the remaining ~3,200
MiB is immovable without pruning functionality.

#### Verdict on the GPU/ML lane

1. **GPU training and development** (`pytorch/pytorch`, `ray:*-cu*`): **OUT OF SCOPE**. Shell
   removal breaks the workflow, the size win is capped at ~8%, and 3 GB of proprietary CUDA,
   cuDNN and MKL would ride inside an FSDK-provenance image.
2. **GPU inference and serving** (`vllm`, `triton`, `tgi`, `ollama`): **CONDITIONAL / DEFERRED**.
   Distroless fits the serving semantics, but the lane is blocked on an explicit decision
   about ingesting proprietary NVIDIA redistributables. Note these images are 3.5–8.8 GiB
   compressed and run as root today.
3. **CPU-only ML and vector/data engines** (`qdrant`, `torchserve:latest-cpu`, `ray:*-cpu`,
   `milvus`, `weaviate`): **IN / HIGH IMPACT**. No proprietary blobs, source-buildable under
   FSDK toolchains, and a shell plus package manager to remove.

---

### Consolidated catalog impact ranking

All targets from #114 and #124, ranked by base weight removed, shell and package-manager
elimination, CVE exposure, FSDK provenance feasibility and pull volume. Sizes are the
compressed figures measured above or in #114.

#### Tier 1 — flagship exemplars and high-volume runtimes
1. **Cloud Custodian** (`cloudcustodian/c7n`) — Ubuntu 24.04 + `apt` + named user. Pure
   Python on the existing lane; five images from one generator (#117, #120).
2. **OpenSearch** — AlmaLinux + `dnf` + bundled JDK. ~84% reduction proven via `-min`
   distribution and JDK strip (#123, #130).
3. **Node.js** (`node:24-bookworm`) — Debian `buildpack-deps`, 390.0 MiB. Enormous pull volume.
4. **Apache Spark** (`apache/spark`, `apache/spark-py`) — Ubuntu 22.04 + OpenJDK (+ Python),
   765.6 / 525.1 MiB.
5. **Apache Airflow** (`apache/airflow:2.10.0-python3.11`) — `python:3.11-slim-bookworm`,
   382.9 MiB, `apt` and shell retained, USER 50000. Reuses the Python lane.
6. **Qdrant** (`qdrant/qdrant`) — `debian:trixie-slim`, 70.7 MiB, one static Rust binary on a
   base with `apt` and a shell, runs as root.

#### Tier 2 — core data engines and infrastructure runtimes
7. **PostgreSQL** — Debian `-slim`, 154.8 MiB. Wave 0 (#146).
8. **MariaDB** — Ubuntu, 102.7 MiB. Wave 0 (#146).
9. **Temurin JRE** (`eclipse-temurin:25-jre`) — Ubuntu 22.04, 120.2 MiB. Shared runtime.
10. **Valkey** — Debian `-slim`, 42.3 MiB.
11. **Harbor core** (`goharbor/harbor-core:v2.12.0`) — Photon OS 5.0 + `tdnf`, 59.5 MiB. CNCF.
12. **HashiCorp Vault** (`hashicorp/vault`) — Alpine 3.24.1 + `apk`, 183.0 MiB. Shell removal
    has the highest value on a secrets engine.
13. **MinIO** (`quay.io/minio/minio`) — `ubi9/ubi-micro`, 59.4 MiB, shell entrypoint, root.
14. **Grafana** (`grafana/grafana`) — Alpine 3.24.1 + `apk`, 453.7 MiB. Large pull volume.

#### Tier 3 — CPU ML and orchestration
15. **TorchServe CPU** (`pytorch/torchserve:latest-cpu`) — Ubuntu 20.04, 669.4 MiB. JRE +
    Python inference without CUDA.
16. **Ray CPU** (`rayproject/ray:2.35.0-cpu`) — Ubuntu 22.04 + Conda, 798.2 MiB. Same conda
    package-cache pattern measured on PyTorch above.
17. **Milvus** (`milvusdb/milvus`) — Ubuntu 22.04, 568.9 MiB, named user.
18. **Weaviate** (`semitechnologies/weaviate`) — Alpine 3.24.2 + `apk`, 85.2 MiB, root.
19. **Volcano** (`vc-controller-manager`, `vc-scheduler`) — Alpine 3.24.1, 28–33 MiB. CNCF
    batch scheduler, clean Go ingestion (#145).
20. **KubeStellar Hive** (`ghcr.io/kubestellar/hive`) — Debian trixie (`node:26-slim`),
    1,496.0 MiB across 68 layers. Multi-runtime agent stack; starts as root.
21. **Dragonfly** (`dragonflyoss/dfdaemon`) — Alpine (published) / Debian slim (current
    source), 48.9 MiB. CNCF P2P distribution client.

#### Tier 4 — exceptions
22. **Falco** (`falcosecurity/falco`) — Wolfi + `apk`, 47.9 MiB. eBPF build makes it the most
    expensive target (#113).

#### Tier 5 — OUT / out of scope (do not build)
- Already distroless: `coredns`, `argo-workflows`, `kyverno` (`ko` + Wolfi static),
  `opentelemetry-collector` (`scratch`), `kube-vip` (`scratch`), `etcd`, `in-toto`,
  `kserve-controller`, `kubeflow-training-operator`.
- GPU training monoliths: `pytorch/pytorch` (GPU), `rayproject/ray:*-cu*` — shell contract
  plus proprietary CUDA; see the verdict above.
- GPU serving (`vllm`, `triton`, `tgi`, `ollama`) is **deferred**, not OUT: it re-enters when
  the proprietary-redistributable decision is made.

---

### Method (#124)

All figures dated **2026-09-20** (UTC), `linux/amd64`. "MiB" is bytes / 1,048,576; the #114
tables use the same unit under the label "MB".

**Resolve a tag to the amd64 manifest digest, sum the compressed layers, read `USER`:**

```sh
ref=grafana/grafana:latest
raw=$(skopeo inspect --raw docker://$ref)
digest=$(jq -r '[.manifests[]|select(.platform.os=="linux" and .platform.architecture=="amd64"
          and ((.annotations["vnd.docker.reference.type"]//"")!="attestation-manifest"))][0].digest' <<<"$raw")
# single-platform images have no .manifests; the digest is then sha256 of the raw manifest itself
skopeo inspect --raw    docker://${ref%:*}@$digest | jq '[.layers[].size]|add/1048576'
skopeo inspect --config docker://${ref%:*}@$digest | jq '{User:.config.User, hist:[.history[].created_by]}'
```

**Digests measured** (repository @ amd64 image-manifest digest; the tag is only how the digest
was found, and every row in the tables above can be re-fetched from this column):

| Ref | Measured digest |
| --- | --- |
| `volcanosh/vc-controller-manager:latest` | `volcanosh/vc-controller-manager@sha256:5b26759c2187820f6ef0fadbc8b1b7b2231a8c054d381e12e1bf3589c15d5c4b` |
| `volcanosh/vc-scheduler:latest` | `volcanosh/vc-scheduler@sha256:9197c9ce30dd7392c6bde085cf4f635a8dbf4007caf711bbc82c0a3776544d9e` |
| `volcanosh/vc-webhook-manager:latest` | `volcanosh/vc-webhook-manager@sha256:cce4ea735138cbe57191d277dc4ce712b4907ba3c9d757efb71549bf45511e6b` |
| `falcosecurity/falco:latest` | `falcosecurity/falco@sha256:9f02feb5544a54a4ca2974bd8ab3a0cca287f3fe7c697d612814357af0cc55e5` |
| `falcosecurity/falco-no-driver:latest` | `falcosecurity/falco-no-driver@sha256:92cc256b9d315a3d0bf0bc8768b4ba432ae75854dd7464e761a5414535cf072e` |
| `ghcr.io/kubestellar/hive:latest` | `ghcr.io/kubestellar/hive@sha256:77d6091ab76e961d0143412821cdaede836636ac074c8d16609982aafcf639fe` |
| `dragonflyoss/dfdaemon:latest` | `dragonflyoss/dfdaemon@sha256:44ebb64c8d8f5d82e67eeebfaf2ece4f88840665e2732a16147f9bd30fae5744` |
| `vllm/vllm-openai:latest` | `vllm/vllm-openai@sha256:082ca6f035279109041ffd3fe0695cb568b29bc580b35c4f297a66a08b216c1b` |
| `nvcr.io/nvidia/tritonserver:24.08-py3` | `nvcr.io/nvidia/tritonserver@sha256:98619804041f21aab09c53a4a5cf814bfff5c6d37aacd22a4ecf664501b4340d` |
| `kserve/kserve-controller:latest` | `kserve/kserve-controller@sha256:7c135659750f612d9b9de816130a331b4ced4b7e5be870780febffcbc1d15cf3` |
| `kserve/storage-initializer:latest` | `kserve/storage-initializer@sha256:5159e12ea3506ceb54265e907a503087d6d9cab68d23c3536ac2deadb6d49b53` |
| `pytorch/torchserve:latest-cpu` | `pytorch/torchserve@sha256:78fa81a563467ed97a89c4e4c4e32b3ca14fb901fc15b4b2927235bcadfc801a` |
| `ghcr.io/huggingface/text-generation-inference:latest` | `ghcr.io/huggingface/text-generation-inference@sha256:e2acc9bff4d1d0e3b51b465c35a5eef907cbe61261801bc5ab95329716a120f8` |
| `ollama/ollama:latest` | `ollama/ollama@sha256:c715bebf769913db6c82d96f8a8dfee989c4bdfe19fa7d700e3d41ee0ceb5461` |
| `seldonio/seldon-core-operator:1.18.2` | `seldonio/seldon-core-operator@sha256:afb4121e53c774b512190ae29f5f73f2c5aae372787c7cc51eaaba91bf955520` |
| `rayproject/ray:2.35.0-cpu` | `rayproject/ray@sha256:cca3f2a182427a39404eca89dd1676f1d437b58057df2723b270b56e9dc63b55` |
| `rayproject/ray:2.35.0-cu121` | `rayproject/ray@sha256:5d944f82153d629ac91c85c1cdb091b655a6faae240db6c0b5012467a8b7c722` |
| `kubeflow/training-operator:latest` | `kubeflow/training-operator@sha256:7373086e570ae465092e215322ec96ba6800c9c00a513e1b5be29c5c220ec47e` |
| `argoproj/workflow-controller:latest` | `argoproj/workflow-controller@sha256:f0160485cd1077d1a682614c4eb6e1d28d3f502a7c91c0ad85bd3fc90f917d9b` |
| `milvusdb/milvus:latest` | `milvusdb/milvus@sha256:fbb7aa4e360a94cc880b914fe25d6d48043573778017f4609f877687a73c1f99` |
| `qdrant/qdrant:latest` | `qdrant/qdrant@sha256:0699e7733a6fa7fa7f6b95dcbed84ebb04584110da525cdfdef9f305c4f57738` |
| `semitechnologies/weaviate:latest` | `semitechnologies/weaviate@sha256:b7b9ee10f7e13f460f8e7ac48b2089f797807289bd909f39a75ddf87fa04c1fa` |
| `apache/airflow:2.10.0-python3.11` | `apache/airflow@sha256:7c77d86d4834444d60859ed66eb776e34e2813e79e66ee0f0b66726b699696b6` |
| `apache/spark:latest` | `apache/spark@sha256:786b96ed0058a0f1411475b218105f556ae4dabb2849c8dd23f4a701e94dd2ca` |
| `apache/spark-py:latest` | `apache/spark-py@sha256:489f904a77f21134df4840de5f8bd9f110925e7b439ca6a04b7c033813edfebc` |
| `prom/prometheus:latest` | `prom/prometheus@sha256:e906cef998316bbe319f98711e1b4d8613ad37e14b08ff831d7036e77b7464f9` |
| `grafana/grafana:latest` | `grafana/grafana@sha256:9924c7fe0effe4a5fea08b3451905de54f09fde9d1589463a5f2d02d9ec158bc` |
| `quay.io/coreos/etcd:v3.5.15` | `quay.io/coreos/etcd@sha256:63ca0fa512664b8351bfa6175e88bea0beeff9857326f973227d47a3181ae602` |
| `hashicorp/vault:latest` | `hashicorp/vault@sha256:8af37ae9d45e4a0fac48ab700e0d99efc4c2d6cd84354a869f2147f1d3abab46` |
| `goharbor/harbor-core:v2.12.0` | `goharbor/harbor-core@sha256:0d5499810373c66674bf7f83310bff2224fbae73bba731a807ecadb3b9aa0c2b` |
| `aquasec/trivy:latest` | `aquasec/trivy@sha256:ee940acbf1f58ebadb42d01434ce4609530bf1b52536afbd1eee66cd7123c5c9` |
| `quay.io/keycloak/keycloak:latest` | `quay.io/keycloak/keycloak@sha256:3d911baa186f352563854039b95f21a7e2c01c76b527fdc64f24a0885b927bdf` |
| `docker.elastic.co/elasticsearch/elasticsearch:8.15.0` | `docker.elastic.co/elasticsearch/elasticsearch@sha256:7dc0d398250eb0641c4dd9080933351238a664e43a77df359ea9f14082d5957d` |
| `docker.elastic.co/logstash/logstash:8.15.0` | `docker.elastic.co/logstash/logstash@sha256:16007182e6789d15f85e3d31ab2cdf55fa930e552f7a9aaf7eeef027a632ba2d` |
| `nvidia/cuda:12.4.1-base-ubuntu22.04` | `nvidia/cuda@sha256:8767a245ed2c481eb245d8f6c625accc3788e1fb8612403d6b4cd4645a4f09c7` |
| `nvidia/cuda:12.4.1-runtime-ubuntu22.04` | `nvidia/cuda@sha256:cff3a0d82d2c2b47bab252d67fa9b34a20ef4c50781d98501b5c7367ea9afd10` |
| `nvidia/cuda:12.4.1-devel-ubuntu22.04` | `nvidia/cuda@sha256:5645fec64549cc35930eee9d85aafd2b0006c0c3f22632be5a1d85e2604e9749` |
| `pytorch/pytorch:latest` | `pytorch/pytorch@sha256:11691e035a3651d25a87116b4f6adc113a27a29d8f5a6a583f8569e0ee5ff897` |
| `quay.io/minio/minio:latest` | `quay.io/minio/minio@sha256:a1a8bd4ac40ad7881a245bab97323e18f971e4d4cba2c2007ec1bedd21cbaba2` |

**Layer 2 traversal (no extraction; the tar stream is categorised in flight):**

```sh
# fetch the blob by digest (resumable; refresh the anonymous pull token per attempt)
tok=$(curl -sf 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:pytorch/pytorch:pull' | jq -r .token)
curl -sfL -C - -H "Authorization: Bearer $tok" -o layer2.tar.gz \
  https://registry-1.docker.io/v2/pytorch/pytorch/blobs/sha256:3d552c93e873f61562c7bc8d1e0a9436c890cb44d1a9c97c9a69b864dfb91277
echo '3d552c93e873f61562c7bc8d1e0a9436c890cb44d1a9c97c9a69b864dfb91277  layer2.tar.gz' | sha256sum -c
gzip -dc layer2.tar.gz | wc -c                      # 7,148.2 MiB uncompressed
```

```python
# categorise every regular file, first matching rule wins (rows are disjoint)
import re, tarfile
RULES = [
  ("conda_pkgs_cache", lambda n: n.startswith("opt/conda/pkgs/")),
  ("conda_bin",        lambda n: n.startswith("opt/conda/bin/")),
  ("tests",            lambda n: re.search(r"(^|/)(tests?|testing)/", n) or n.endswith("_test.py") or re.search(r"(^|/)test_[^/]*\.py$", n)),
  ("docs_man",         lambda n: re.search(r"(^|/)(doc|docs|man|share/doc|share/man|share/info)/", n) or (n.endswith((".md", ".rst", ".txt")) and "/site-packages/" not in n)),
  ("headers_include",  lambda n: re.search(r"(^|/)include/", n) or n.endswith((".h", ".hpp", ".cuh", ".inl", ".hh"))),
  ("static_archives",  lambda n: n.endswith(".a")),
  ("bytecode_pyc",     lambda n: "/__pycache__/" in n or n.endswith((".pyc", ".pyo"))),
  ("torch_lib_so",     lambda n: re.search(r"/site-packages/torch/lib/[^/]*\.so", n)),
  ("conda_lib_so",     lambda n: re.match(r"opt/conda/lib/[^/]*\.so", n)),
  ("other_so",         lambda n: re.search(r"\.so(\.\d+)*$", n)),
  ("python_sources",   lambda n: n.endswith((".py", ".pyi"))),
  ("other",            lambda n: True),
]
sizes = {k: 0 for k, _ in RULES}
with tarfile.open("layer2.tar.gz", "r|gz") as tf:
    for m in tf:
        if not m.isreg(): continue
        n = m.name.lstrip("./")
        sizes[next(k for k, f in RULES if f(n))] += m.size
```

The "build tooling in `opt/conda/bin`" figure (66.3 MiB) is the subset of that directory
matching the CMake suite, `x86_64-conda-linux-gnu-*`, the pcre2 test binaries, libarchive
(`bsdtar`, `bsdcpio`), `patch`, `2to3*`, compression and codec CLIs and `*-config` scripts; the
`python3.10` interpreter (16.4 MiB) and 4.2 MiB of small utilities are left in place.

**Compressed saving:** the strippable members were written to a second tar with
`tarfile.open(out, "w|gz", compresslevel=6)` and its size taken with `stat -c %s` — 292.1 MiB
for 897.6 MiB of input.

**Layers 0 and 1:** fetched by digest as above; `gzip -dc | wc -c` for uncompressed size,
`tar -tvzf` for the `.a`/`include/` split of Layer 1, and `tar -xzOf layer0.tar.gz
usr/lib/os-release` for the Ubuntu point release.

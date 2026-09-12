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
| kubestellar-hive | Alpine | **IN** | [kubestellar/hive](https://github.com/kubestellar/hive/blob/v2/v2/Dockerfile) |
| falco | Chainguard Wolfi — **but `apk` retained in final image** | **EXCEPTION** | [falco Dockerfile](https://github.com/falcosecurity/falco/blob/master/docker/falco/Dockerfile) |
| coredns | `gcr.io/distroless/static-debian12`, USER 65532 | OUT | [coredns](https://github.com/coredns/coredns/blob/master/Dockerfile) |
| argo-workflows (controller) | `gcr.io/distroless/static-debian13`, USER 8737 | OUT | [argo-workflows](https://github.com/argoproj/argo-workflows/blob/main/Dockerfile) |
| argo-workflows (argoexec) | `gcr.io/distroless/static-debian13`; root and UID-8737 targets both published | OUT | same |
| kyverno | `ko` + Wolfi static | OUT | [.ko.yaml](https://github.com/kyverno/kyverno/blob/main/.ko.yaml) |
| opentelemetry-collector (otelcol) | `scratch`, USER 10001 | OUT | [collector-releases](https://github.com/open-telemetry/opentelemetry-collector-releases/tree/main/distributions) |
| opentelemetry-collector (contrib) | `scratch`, USER 10001 | OUT | same |
| kube-vip | `scratch` | OUT | [kube-vip](https://github.com/kube-vip/kube-vip/blob/main/Dockerfile) |
| dragonfly (dfdaemon) | not located | **HOLD** | — |
| in-toto | no upstream OCI build found; upstream publishes Python artifacts only | **HOLD** | — |

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
13. **KubeStellar Hive** — Alpine, multi-runtime.
14. **Falco** — by exception; eBPF makes it the most expensive.

## Known gap

**Uncompressed image sizes were not measured.** The research environment could not pull
images. Every size-delta claim in this catalog remains unverified until someone runs the
comparison. This must be closed before any public delta claim is published.

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

Resolves [#124](https://github.com/projectbluefin/fsdk-containers/issues/124). Extends the catalog audit to AI/ML serving, training/orchestration, vector databases, CNCF-adjacent infrastructure with fat bases, and base runtime layers.

Evidence gathered from authoritative upstream Dockerfiles, build configurations, and container registries, accompanied by exact registry measurement via `skopeo inspect --raw` (`linux/amd64`).

### Resolution of #114 Unmeasured and HOLD Targets

Three targets were unmeasured during initial charting, and two were on HOLD:

1. **Volcano (`volcanosh/vc-controller-manager`, `volcanosh/vc-scheduler`, `volcanosh/vc-webhook-manager`)**:
   - **Base**: `alpine:3.24.1` (3.7 MB base layer).
   - **Measurements (compressed)**:
     - `volcanosh/vc-controller-manager:latest`: **28.0 MB** (Layer 0: 3.7 MB base, Layer 1: 24.4 MB Go binary).
     - `volcanosh/vc-scheduler:latest`: **32.6 MB** (Layer 0: 3.7 MB base, Layer 1: 28.9 MB Go binary).
     - `volcanosh/vc-webhook-manager:latest`: **46.7 MB** (Layer 0: 3.7 MB base, Layer 1-2: 43.0 MB payload).
   - **Verdict**: **IN**. Carries Alpine shell and `apk`. Small binary payloads with clean Go builds.

2. **Falco (`falcosecurity/falco`)**:
   - **Base**: `cgr.dev/chainguard/wolfi-base` with post-base `apk add curl ca-certificates jq libstdc++`.
   - **Measurements (compressed)**:
     - `falcosecurity/falco:latest`: **47.9 MB** (14 layers, USER `0:0`).
     - `falcosecurity/falco-no-driver:latest`: **71.5 MB** (3 layers).
   - **Verdict**: **EXCEPTION (IN)**. Retains package manager (`apk`), shell, and CLI tooling in the final stage. (eBPF probe is buildable, kmod is deferred per #113).

3. **KubeStellar Hive (`ghcr.io/kubestellar/hive`)**:
   - **Base**: `node:26-slim` (Debian Trixie, 28.4 MB base layer).
   - **Measurements (compressed)**:
     - `ghcr.io/kubestellar/hive:latest`: **1,559.9 MB** (68 layers, USER `dev:node`).
   - **Verdict**: **IN**. Full agent orchestration runtime containing Node, Python venvs (LiteLLM, Nous framework), Go toolchain, tmux, and git. High CVE and attack surface in upstream image.

4. **Dragonfly (`dragonflyoss/dfdaemon`, `dragonflyoss/Dragonfly2`)**:
   - **Build Source**: [dragonflyoss/Dragonfly2 manager/Dockerfile](https://github.com/dragonflyoss/Dragonfly2/blob/main/build/images/manager/Dockerfile).
   - **Base**: `alpine:3.23.4` with `apk add curl`.
   - **Measurements (compressed)**:
     - `dragonflyoss/dfdaemon:latest`: **48.9 MB** (4 layers).
   - **Verdict**: **IN** (Resolved from HOLD). Replaces Alpine base and removes `apk`/curl.

5. **in-toto (`in-toto/in-toto-golang`)**:
   - **Build Source**: [in-toto/in-toto-golang Dockerfile](https://github.com/in-toto/in-toto-golang/blob/master/Dockerfile).
   - **Base**: `FROM gcr.io/distroless/base`.
   - **Verdict**: **OUT** (Resolved from HOLD). Upstream already ships on Google Distroless base; no packaging delta to win.

---

### AI/ML and CNCF-Adjacent Matrix

All sizes are compressed registry transfer sizes for `linux/amd64` (skopeo inspect recipe). Benchmarked against `-slim`/`-min`/`-cpu` variants where available.

| Target | Upstream Ref / Variant | Final-Stage Base | Shell / Pkg Mgr | USER | Compressed Size | Verdict | Upstream Build Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Inference / Serving** | | | | | | | |
| vllm | `vllm/vllm-openai:latest` | `nvidia/cuda:*-base-ubuntu*` | `bash`, `apt`, deadsnakes PPA | `vllm` | 8,272.3 MB | **CONDITIONAL** | [vllm/docker/Dockerfile](https://github.com/vllm-project/vllm/blob/main/docker/Dockerfile) |
| triton-inference-server | `nvcr.io/nvidia/tritonserver:24.08-py3` | Ubuntu 22.04 | `bash`, `apt` | root | 8,735.8 MB | **CONDITIONAL** | [triton Dockerfile](https://github.com/triton-inference-server/server/blob/main/Dockerfile) |
| kserve (controller) | `kserve/kserve-controller:latest` | `gcr.io/distroless/static:nonroot` | None | `65532` | 41.4 MB | **OUT** | [kserve/Dockerfile](https://github.com/kserve/kserve/blob/master/Dockerfile) |
| kserve (storage-init) | `kserve/storage-initializer:latest` | `python:3.11-slim-bookworm` | `sh`, `apt` | `1000` | 92.0 MB | **IN** | [python/storage-initializer.Dockerfile](https://github.com/kserve/kserve/blob/master/python/storage-initializer.Dockerfile) |
| torchserve (cpu) | `pytorch/torchserve:latest-cpu` | Ubuntu 22.04 | `bash`, `apt` | `model-server` | 669.4 MB | **IN** | [torchserve/docker/Dockerfile](https://github.com/pytorch/serve/blob/master/docker/Dockerfile) |
| tgi (text-gen-inf) | `ghcr.io/huggingface/text-generation-inference:latest` | Ubuntu 22.04 | `bash`, `apt` | root | 8,825.6 MB | **CONDITIONAL** | [tgi/Dockerfile](https://github.com/huggingface/text-generation-inference/blob/main/Dockerfile) |
| ollama | `ollama/ollama:latest` | Ubuntu 24.04 | `bash`, `apt` | root | 3,531.8 MB | **CONDITIONAL** | [ollama/Dockerfile](https://github.com/ollama/ollama/blob/main/Dockerfile) |
| seldon-core-operator | `seldonio/seldon-core-operator:1.18.2` | UBI 8 minimal | `sh`, `microdnf` | `8888` | 161.4 MB | **IN** | [seldon-core](https://github.com/SeldonIO/seldon-core) |
| **Training / Orchestration** | | | | | | | |
| ray (cpu) | `rayproject/ray:2.35.0-cpu` | Ubuntu 22.04 + full Conda | `bash`, `apt`, `conda` | `1000` | 798.2 MB | **IN** | [ray/docker/ray/Dockerfile](https://github.com/ray-project/ray/blob/master/docker/ray/Dockerfile) |
| ray (gpu) | `rayproject/ray:2.35.0-cu121` | Ubuntu 22.04 + CUDA devel | `bash`, `apt`, `conda` | `1000` | 5,983.8 MB | **OUT OF SCOPE** | [ray/docker/ray/Dockerfile](https://github.com/ray-project/ray/blob/master/docker/ray/Dockerfile) |
| kubeflow (training-op) | `kubeflow/training-operator:latest` | `gcr.io/distroless/static:nonroot` | None | `65532` | 31.1 MB | **OUT** | [training-operator/cmd/trainer-controller-manager/Dockerfile](https://github.com/kubeflow/training-operator/blob/master/cmd/trainer-controller-manager/Dockerfile) |
| volcano (controller) | `volcanosh/vc-controller-manager:latest` | `alpine:3.24.1` | `sh`, `apk` | root | 28.0 MB | **IN** | [volcano installer](https://github.com/volcano-sh/volcano/blob/master/installer/dockerfile/controller-manager/Dockerfile) |
| volcano (scheduler) | `volcanosh/vc-scheduler:latest` | `alpine:3.24.1` | `sh`, `apk` | root | 32.6 MB | **IN** | [volcano installer](https://github.com/volcano-sh/volcano/blob/master/installer/dockerfile/scheduler/Dockerfile) |
| argo-workflows | `argoproj/workflow-controller:latest` | `gcr.io/distroless/static-debian13` | None | `8737` | 43.3 MB | **OUT** | [argo-workflows/Dockerfile](https://github.com/argoproj/argo-workflows/blob/main/Dockerfile) |
| **Vector & Data Engines** | | | | | | | |
| milvus | `milvusdb/milvus:latest` | Ubuntu 22.04 (jammy) | `bash`, `apt` | `milvus:milvus` | 1,080.6 MB | **IN** | [milvus/build/docker/milvus/ubuntu22.04/Dockerfile](https://github.com/milvus-io/milvus/blob/master/build/docker/milvus/ubuntu22.04/Dockerfile) |
| qdrant | `qdrant/qdrant:latest` | `debian:trixie-slim` | `sh`, `apt` | `0:0` | 70.7 MB | **IN** | [qdrant/Dockerfile](https://github.com/qdrant/qdrant/blob/master/Dockerfile) |
| weaviate | `semitechnologies/weaviate:latest` | `alpine:3.20` | `sh`, `apk` | root | 87.1 MB | **IN** | [weaviate/Dockerfile](https://github.com/weaviate/weaviate/blob/master/Dockerfile) |
| minio | `minio/minio:latest` | `registry.access.redhat.com/ubi9-micro` | `sh` entrypoint | root | 59.4 MB | **IN** | [minio/Dockerfile](https://github.com/minio/minio/blob/master/Dockerfile) |
| **CNCF-Adjacent Infra with Fat Bases** | | | | | | | |
| airflow | `apache/airflow:2.10.0-python3.11` | `debian:bookworm-slim` | `bash`, `apt` | `50000` | 382.9 MB | **IN** | [airflow/Dockerfile](https://github.com/apache/airflow/blob/main/Dockerfile) |
| spark (core) | `apache/spark:latest` | `ubuntu:24.04` (OpenJDK 17) | `bash`, `apt` | `spark` | 765.6 MB | **IN** | [spark/Dockerfile](https://github.com/apache/spark/blob/master/resource-managers/kubernetes/docker/src/main/dockerfiles/spark/Dockerfile) |
| spark-py | `apache/spark-py:latest` | `ubuntu:24.04` (OpenJDK + Python) | `bash`, `apt` | `185` | 525.1 MB | **IN** | [spark-py/Dockerfile](https://github.com/apache/spark/blob/master/resource-managers/kubernetes/docker/src/main/dockerfiles/spark/Dockerfile) |
| prometheus | `prom/prometheus:latest` | Busybox 1.38 / Buildroot | `sh` (busybox) | `nobody` | 104.3 MB | **IN** | [prometheus/Dockerfile](https://github.com/prometheus/prometheus/blob/main/Dockerfile) |
| grafana | `grafana/grafana:latest` | `alpine:3.20` | `sh`, `apk` | `472` | 452.0 MB | **IN** | [grafana/Dockerfile](https://github.com/grafana/grafana/blob/main/Dockerfile) |
| etcd | `quay.io/coreos/etcd:v3.5.15` | `gcr.io/distroless/static-debian12` | None | root | 20.3 MB | **OUT** | [etcd/Dockerfile](https://github.com/etcd-io/etcd/blob/main/Dockerfile) |
| vault | `hashicorp/vault:latest` | `registry.access.redhat.com/ubi10/ubi-minimal` | `sh`, `microdnf` | `vault` | 182.9 MB | **IN** | [vault/Dockerfile](https://github.com/hashicorp/vault/blob/main/Dockerfile) |
| harbor (core) | `goharbor/harbor-core:v2.12.0` | `goharbor/photon:5.0` | `sh`, `tdnf` | `10000` | 59.5 MB | **IN** | [harbor/make/photon/core/Dockerfile](https://github.com/goharbor/harbor/blob/main/make/photon/core/Dockerfile) |
| trivy | `aquasec/trivy:latest` | `alpine:3.24.1` | `sh`, `apk` | root | 58.3 MB | **IN** | [trivy/Dockerfile](https://github.com/aquasecurity/trivy/blob/main/Dockerfile) |
| keycloak | `quay.io/keycloak/keycloak:latest` | `registry.access.redhat.com/ubi9-micro` | `sh` | `1000` | 255.5 MB | **IN** | [keycloak/quarkus/container/Dockerfile](https://github.com/keycloak/keycloak/blob/main/quarkus/container/Dockerfile) |
| elasticsearch | `docker.elastic.co/elasticsearch/elasticsearch:8.15.0` | `ubuntu:24.04` (bundled JDK) | `bash`, `apt` | `1000` | 638.1 MB | **IN** | [elasticsearch/distribution/docker](https://github.com/elastic/elasticsearch/tree/main/distribution/docker) |
| logstash | `docker.elastic.co/logstash/logstash:8.15.0` | `ubuntu:24.04` (OpenJDK + JRuby) | `bash`, `apt` | `1000` | 498.3 MB | **IN** | [logstash/docker](https://github.com/elastic/logstash/tree/main/docker) |
| **Base Layers (`nvidia/cuda`)** | | | | | | | |
| cuda (base) | `nvidia/cuda:12.4.1-base-ubuntu22.04` | Ubuntu 22.04 | `bash`, `apt` | root | 87.5 MB | Reference | — |
| cuda (runtime) | `nvidia/cuda:12.4.1-runtime-ubuntu22.04` | Ubuntu 22.04 | `bash`, `apt` | root | 1,398.2 MB | Reference | — |
| cuda (devel) | `nvidia/cuda:12.4.1-devel-ubuntu22.04` | Ubuntu 22.04 | `bash`, `apt` | root | 3,921.9 MB | Reference | — |

---

### Anatomy of PyTorch Internals & Lossless Strip Measurements

Issue #124 reopened the investigation into `pytorch/pytorch:latest` (3,490.5 MB compressed). The earlier assertion that the win was "<0.5%" rested on comparing only the base layer (~13 MB) against the total image. To test whether the OpenSearch lesson applies here (where the win came from distribution choice and packaging bloat rather than the OS base), the layers were inspected, unpacked, and measured.

#### Layer Breakdown of `pytorch/pytorch:latest`

| Layer | Digest (prefix) | Compressed Size | Description |
| --- | --- | --- | --- |
| 0 | `sha256:d66d6a6a...` | **30.5 MB** | Ubuntu 22.04/24.04 base rootfs (uncompressed ~77 MB) |
| 1 | `sha256:3ad96c6a...` | **7.2 MB** | `apt-get install`: `ca-certificates`, `libjpeg-dev`, `libpng-dev`, `gcc` |
| 2 | `sha256:3d552c93...` | **3,622.3 MB** | Conda environment & Python runtime payload (`/opt/conda`) |
| 3 | `sha256:4f4fb700...` | <1 KB | Metadata / symlinks |
| 4 | `sha256:42a8919f...` | <1 KB | Working directory `/workspace` |
| **Total** | | **3,490.5 MB** | |

#### Internal Composition of the Payload (Layer 2)

Layer 2 decompresses to **7,148.2 MB** (7.15 GB) across 45,593 files. A complete streaming traversal categorised every file and directory:

| Component / Category | Uncompressed Size | % of Payload | Analysis & Strip Eligibility |
| --- | --- | --- | --- |
| **Conda system shared libs (`opt/conda/lib/*.so`)** | **3,001.1 MB** | 42.0% | CUDA shared objects (`libcublasLt.so` 484MB, `libcusolver.so` 290MB, `libcusparse.so` 243MB, `libcufft.so` 184MB, etc.). **Required at runtime.** |
| **PyTorch native libs (`torch/lib/*.so`)** | **2,579.1 MB** | 36.1% | `libtorch_cuda.so` (1,028.9 MB), `libcudnn_*.so` (~1,100 MB), `libtorch_cpu.so` (273.6 MB). **Required at runtime.** |
| **Conda package cache (`opt/conda/pkgs/`)** | **570.6 MB** | **8.0%** | **Pure packaging bloat.** Cached `.tar.bz2` tarballs and unpacked duplicate package trees left behind. Includes duplicate `libtriton.so` (378.3 MB). **Losslessly strippable.** |
| **Other shared objects** | 427.0 MB | 6.0% | Triton JIT, Python extension modules, auxiliary libraries. Required. |
| **Other files (configs, assets)** | 217.4 MB | 3.0% | CUDA configs, tzdata, Conda environment state. |
| **Python sources (`.py`)** | 96.4 MB | 1.3% | Runtime Python code. Required. |
| **Static archives (`*.a`)** | **82.8 MB** | **1.2%** | Static libraries in `/opt/conda/lib` (`libculibos.a`, `libopenblas.a`, etc.). Never linked at runtime. **Losslessly strippable.** |
| **Bytecode cache (`__pycache__`, `.pyc`)** | **77.7 MB** | **1.1%** | Re-creatable bytecode cache. **Losslessly strippable.** |
| **Headers & includes (`include/`, `*.h`, `*.cuh`)** | **48.1 MB** | **0.7%** | CUDA C++ headers, Python headers (`include/python3.10`). Build-time only. **Losslessly strippable.** |
| **Test suites (`test/`, `tests/`, `*_test.py`)** | **36.7 MB** | **0.5%** | Bundled PyTorch, NumPy, and SciPy unit tests inside `site-packages`. Never imported in production. **Losslessly strippable.** |
| **Documentation & man pages (`doc/`, `man/`)** | **11.5 MB** | **0.2%** | Help manuals, groff files, Markdown docs. **Losslessly strippable.** |
| **Dev binaries in `opt/conda/bin`** | ~50.0 MB | ~0.7% | Build tools: `2to3`, `bsdtar`, `bsdcpio`, `bunzip2`, `c_rehash`. **Losslessly strippable.** |
| **Total** | **7,148.2 MB** | **100.0%** | |

#### What a Lossless Strip Recovers

Applying the exact same lossless packaging rules as OpenSearch (removing build-time artifacts, package caches, tests, docs, and static archives without touching runtime code or kernels):

1. `opt/conda/pkgs/` (Conda package cache): 570.6 MB
2. Static `.a` archives: 82.8 MB
3. Header files and `include/` trees: 48.1 MB
4. Bundled test suites: 36.7 MB
5. Python bytecode cache: 77.7 MB
6. Documentation and man pages: 11.5 MB
7. Dev binaries in `opt/conda/bin` and Layer 1 (`-dev` packages): ~50 MB
8. **Total uncompressed reduction**: **~877 MB (-12.3% of payload)**
9. **Projected compressed registry saving**: **~450–500 MB (~14–15% total image reduction)**

#### The Comparison with OpenSearch

| Metric | OpenSearch (#114) | PyTorch (#124) |
| --- | --- | --- |
| Upstream fat image | 1,084 MB | 3,490 MB |
| Non-runtime payload fraction | **68%** (JDK build tools, jmods, plugins) | **~12%** (caches, tests, static libs) |
| Upstream minimal distribution available? | **Yes** (`-min` tarball) | **No** (single monolithic conda/wheel distribution) |
| Core runtime payload compressible? | High (text/code/java bytecode) | Low (pre-compiled binary kernels & dense weights) |
| Distroless base + lossless strip reduction | **~84%** (1,084 MB -> 175 MB) | **~15%** (3,490 MB -> ~3,000 MB) |

The measurement overturns the earlier unmeasured "<0.5%" claim: build artifact and cache removal yields a real **~500 MB (~15%)** reduction. However, unlike OpenSearch, the remaining **~3,000 MB** is runtime native CUDA binary code (`libtorch_cuda.so`, `libcudnn`, `libcublasLt`). It cannot be removed without pruning functionality.

---

### The Hard Question: Does the Distroless Value Proposition Survive for GPU/ML?

**No for training and development; conditionally yes for headless inference serving.**

The three genuine risks outlined in the issue were evaluated against physical measurements:

#### 1. The Provenance Trap (CUDA Proprietary Binaries)
NVIDIA CUDA is proprietary, closed-source software distributed under a restrictive redistributable license. FSDK's central thesis is **100% source-built, reproducible, auditable provenance** (#113, #115). FSDK cannot compile CUDA kernels, cuDNN, or cuBLAS from source. Ingesting pre-built NVIDIA blobs creates an unavoidable supply-chain compromise:
- In Go targets (#115), prebuilt binary ingestion was explicitly rejected to protect FSDK's provenance guarantee.
- In CUDA, the prebuilt blob is not an edge binary; it is **over 3.0 GB compressed (over 6.0 GB uncompressed)**—comprising >85% of the total container. An "FSDK PyTorch" would be a 15 MB FSDK base carrying 3 GB of unverifiable NVIDIA binary redistributables.

#### 2. The Interactive Shell Contract (`kubectl exec`)
Training and development workflows are fundamentally interactive. In Kubernetes ML clusters (Kubeflow, Slurm-on-k8s, Ray Train), data scientists and ML engineers routinely rely on:
- `kubectl exec -it <pod> -- /bin/bash` to troubleshoot hung workers, examine checkpoint files, or inspect GPU utilization via `nvidia-smi`.
- Dropping into an interactive shell to launch ad-hoc training scripts or debug Python import paths.
- Stripping `/bin/sh`, `/bin/bash`, and coreutils renders training pods unusable for practitioners unless a dedicated debug sidecar is injected.
- **Contrast with Serving**: Headless inference runtimes (vLLM, Triton, KServe storage initializer) run dedicated HTTP/gRPC daemons as PID 1 behind API gateways. They do not require interactive shells. In fact, removing the shell and package manager in production inference eliminates severe post-exploitation vectors (remote code execution via model weights deserialization).

#### 3. Vendored Native Libraries in `site-packages`
In general Linux software, dynamic libraries reside in `/usr/lib` or `/lib`. In the Python ML ecosystem, PyTorch, cuDNN, and TensorRT are packaged as manylinux wheels that bundle their own `.so` files inside `/opt/conda/lib/python*/site-packages/` or `/usr/local/lib/python*/site-packages/`. The OS-level SLIM recipe (`rm -rf /usr/share/man /var/lib/apt ...`) operates exclusively on the system rootfs and never reaches `site-packages`. Consequently:
- Replacing Ubuntu 24.04 with FSDK base saves ~13 MB compressed (<0.4% of a 3.5 GB image).
- A packaging-level lossless strip of caches and test suites recovers ~450–500 MB (~15%).
- Over **3,000 MB compressed** remains immutable unless functionality is pruned.

#### The Explicit Verdict on the GPU/ML Lane

1. **GPU Training & Development (`pytorch/pytorch:latest`, `ray:gpu`): OUT OF SCOPE / REJECTED.**
   - **Reason**: Shell removal breaks standard training workflows; size reduction is capped at ~15%; and shipping 3 GB of proprietary CUDA binaries violates FSDK provenance.
2. **GPU Inference & Serving (`vllm`, `triton`, `tgi`): CONDITIONAL / DEFERRED.**
   - **Reason**: Distroless fits serving semantics (headless, no shell needed in production). However, the lane is blocked on an architectural decision regarding proprietary NVIDIA redistributable ingestion.
3. **CPU-Only ML & Vector Data Engines (`qdrant`, `torchserve:cpu`, `ray:cpu`, `milvus`): IN / HIGH IMPACT.**
   - **Reason**: Completely avoids proprietary CUDA blobs; builds cleanly from source under FSDK toolchains; delivers high CVE reduction and clean non-root user contracts.

---

### Consolidated Catalog Impact Ranking

Synthesizing all targets from #114 and #124, ranked by practical impact: base weight removed, shell and package manager elimination, CVE exposure reduction, FSDK provenance feasibility, and deployment pull volume.

#### Tier 1: Flagship Exemplars & High-Volume Runtimes (Immediate Focus)
1. **Cloud Custodian (`cloudcustodian/c7n`)** — Ubuntu 24.04 + `apt` + named user `custodian`. CNCF, pure Python (reuses existing `python.bst` lane), 5 images from one generator. Validates marginal-cost collapse (#117, #120).
2. **OpenSearch** — AlmaLinux + `dnf` + bundled JDK. Proven ~84% reduction via `-min` distribution and JDK lossless strip (#123, #130).
3. **Node.js (`node:24-bookworm`)** — Debian `buildpack-deps` (390 MB compressed). Massive global deployment volume. Pure source build.
4. **Apache Spark (`apache/spark`, `apache/spark-py`)** — Ubuntu 24.04 base (765 MB compressed) with full OpenJDK and Python runtimes. High enterprise footprint.
5. **Apache Airflow (`apache/airflow:2.10.0-python3.11`)** — Debian bookworm-slim base (382.9 MB compressed), `apt` and shell retained, USER 50000. Reuses Python lane.
6. **Qdrant (`qdrant/qdrant:latest`)** — Debian Trixie base (70.7 MB compressed). Single static Rust binary (`qdrant` 33 MB) running on a fat Debian base with `apt` and shell. Clean distroless conversion yields ~50% reduction and zero CVEs.

#### Tier 2: Core Data Engines & Infrastructure Runtimes
7. **PostgreSQL (`postgres:latest`)** — Debian `-slim` (154.8 MB compressed). Verified in Wave 0 (#146).
8. **MariaDB (`mariadb:latest`)** — Ubuntu base (102.7 MB compressed). Proven in Wave 0 (#146).
9. **Temurin JRE (`eclipse-temurin:25-jre`)** — Ubuntu 22.04 (120.2 MB compressed). Key shared runtime component.
10. **Valkey (`valkey/valkey:latest`)** — Debian `-slim` (42.3 MB compressed). High-velocity Redis successor.
11. **Harbor Core (`goharbor/harbor-core:v2.12.0`)** — VMware Photon OS 5.0 (59.5 MB compressed) with `tdnf` package manager and shell. CNCF registry.
12. **HashiCorp Vault (`hashicorp/vault:latest`)** — Red Hat UBI minimal / Alpine (182.9 MB compressed). Security-sensitive workload where shell removal is highest value.
13. **MinIO (`minio/minio:latest`)** — UBI micro (59.4 MB compressed) with shell entrypoint. Go-based S3 store.
14. **Grafana (`grafana/grafana:latest`)** — Alpine base (452.0 MB compressed) with `apk` and shell. Large pull volume.

#### Tier 3: CPU ML & Cloud Orchestration
15. **TorchServe CPU (`pytorch/torchserve:latest-cpu`)** — Ubuntu 22.04 (669.4 MB compressed). Combines JRE + Python CPU inference; avoids CUDA proprietary blobs.
16. **Ray CPU (`rayproject/ray:2.35.0-cpu`)** — Ubuntu 22.04 with Conda (798.2 MB compressed). Replaces fat distro base and strips Conda cache.
17. **Volcano (`volcanosh/vc-controller-manager`, `vc-scheduler`)** — Alpine base (28–33 MB compressed). CNCF batch scheduler, clean Go ingestion (#145).
18. **KubeStellar Hive (`ghcr.io/kubestellar/hive:latest`)** — Debian slim base (1,559.9 MB compressed). Multi-runtime agent stack.
19. **Dragonfly (`dragonflyoss/dfdaemon`)** — Alpine base (48.9 MB compressed). CNCF P2P distribution client.

#### Tier 4: Exceptions & High Maintenance
20. **Falco (`falcosecurity/falco:latest`)** — Wolfi base with `apk` added (47.9 MB compressed). Highest engineering cost due to eBPF build requirements (#113).

#### Tier 5: OUT / Out of Scope (Do Not Build)
- **Already Distroless CNCF Images**:
  - `coredns` (`gcr.io/distroless/static-debian12`) — OUT
  - `argo-workflows` (`gcr.io/distroless/static-debian13`) — OUT
  - `kyverno` (`ko` + Wolfi static) — OUT
  - `opentelemetry-collector` (`scratch`) — OUT
  - `kube-vip` (`scratch`) — OUT
  - `etcd` (`gcr.io/distroless/static-debian12`) — OUT
  - `in-toto` (`gcr.io/distroless/base`) — OUT
  - `kubeflow-training-operator` (`gcr.io/distroless/static:nonroot`) — OUT
- **GPU Training Monoliths**:
  - `pytorch/pytorch:latest` (GPU) — OUT OF SCOPE (interactive shell requirement, proprietary CUDA blobs)
  - `ray:gpu` — OUT OF SCOPE


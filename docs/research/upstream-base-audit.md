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

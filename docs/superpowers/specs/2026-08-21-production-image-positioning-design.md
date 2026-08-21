# Where fsdk-containers sits, and what "best" has to mean — design

**Date:** 2026-08-21
**Status:** awaiting owner review
**Scope:** product positioning and the gap-closure work implied by it. Not a CI
design — see `2026-08-21-fsdk-containers-image-factory-design.md` for the factory.

---

## 0. Why this document exists

The repo's stated intent is "a production set of container images." A competitor
now occupies the same thesis with a hundred-fold larger catalog. This document
answers two questions with measured evidence rather than assertion:

1. Where do we actually sit today?
2. What has to change for "best" to be a defensible claim rather than a wish?

Every number below was measured from the live registries on 2026-08-21 by reading
OCI manifests directly, not from documentation.

---

## 1. The competitor: Red Hat Project Hummingbird

**"Keynote: How I learned to stop worrying and love CVEs — Hummingbird,"** Stef
Walter and Valentin Rothberg, DevConf.CZ 2026, 18 June 2026.
Talk record: <https://pretalx.devconf.info/devconf-cz-2026/talk/XAJLYJ/>.
Project announced 19 Nov 2025; source at
<https://gitlab.com/redhat/hummingbird/containers>.

Its argument is *not* "smaller images." It is that ~50,000 CVEs per year makes
manual assessment and backporting unscalable, so the only viable answer is to
track upstream closely, automate the entire supply chain, and ship images with
zero *known* CVEs at publication time.

**That is our thesis too.** The difference is substrate: Hummingbird derives spec
files from Fedora and then builds and maintains its own RPM universe; we inherit
FSDK's already-patched components and never maintain a package set at all.

As of its generated report of 2026-07-29: **90 images, 254 variants, 22,086
builds, 10,497 automated updates.** Konflux-built with claimed SLSA Build L3,
per-architecture SPDX 2.3 SBOMs as OCI artifacts, CPE metadata for VEX matching,
and FIPS variants. Supported images require a Red Hat subscription
(`registry.access.redhat.com/hi/`); community mirrors exist on Quay.

Their catalog already includes curl, Go, Python, nginx, Node, PostgreSQL and
MariaDB — **every target in our Wave 0 spike set** (#146).

One nuance worth remembering before we repeat their marketing: Hummingbird's own
`core-runtime` compatibility report lists `CMD /bin/bash`, so "all their defaults
are shell-less" is not a claim we should make on their behalf.

---

## 2. Where we sit — measured, not claimed

### 2.1 Size, compressed amd64 layer bytes, read from the registry

| Tier | fsdk-containers | Hummingbird | Google distroless | Chainguard |
| --- | --- | --- | --- | --- |
| static | **16.4 MiB** | — | 0.7 MiB | 0.6 MiB |
| base / glibc | **16.3 MiB** (26.08beta.3: 17.5) | 12 MB (`core-runtime`) | 7.8 MiB | 4.5 MiB (`glibc-dynamic`) |
| python | **37.7 MiB** | — | 18.8 MiB | 24.9 MiB |
| skopeo | **57.0 MiB** | — | — | — |
| qemu-img | **51.3 MiB** | — | — | — |
| buildah | **69.1 MiB** | — | — | — |
| catalog size | **7 images** (5 genuinely distroless) | 90 images / 254 variants | ~12 | hundreds |

We are the largest distroless suite in the comparison. "Slim by default" is not
currently true relative to the field, and our `static` tier is 23× the size of
the thing it is named after.

### 2.2 What is actually inside `base:26.08beta.3`

43.88 MB uncompressed, 4,520 files. By category:

| Category | MB | Note |
| --- | ---: | --- |
| `/usr/bin` (185 binaries) | 12.42 | coreutils, kept by documented contract |
| p11-kit CA machinery | 6.79 | build-time tooling, not runtime |
| libstdc++ / libgomp / libquadmath / libmvec | 4.86 | C++ and OpenMP runtimes in a C base image |
| ncurses / tinfo / readline / terminfo | 4.82 | terminfo (3.37 MB, 2,943 entries) is deliberate |
| CA bundles, four parallel formats | 4.33 | ~0.22 MB is load-bearing |
| locale data | 3.34 | `en_US.utf8/LC_COLLATE` alone is 2.59 MB |
| selinux / sepol | 1.10 | no policy enforcement in the image |
| **debug symbols** | **0.95** | **leak — see §3.2** |
| tzdata | 0.86 | kept by documented contract |
| gconv charsets | 0.23 | kept by documented contract |

Categories overlap slightly; terminfo is counted inside the ncurses row.

**Good news, verified:** no shell, no package manager, no sanitizer or Fortran
runtimes. Those gates hold. Multi-arch (`linux/amd64` + `linux/arm64`) is
genuinely complete across all seven images, tag lines are consistent, and cosign
signatures, SPDX SBOMs and GitHub provenance are live.

### 2.3 The CA store, specifically

We ship four parallel copies of the trust store plus the machinery to regenerate
them:

- `ca-bundle.trust.p11-kit` — 2.5 MB, the *source* format, read by nothing at runtime
- `openssl/ca-bundle.trust.crt` — 676 KB
- `pem/objsign-ca-bundle.pem` — 505 KB, code-signing CAs, not TLS
- `java/cacerts` — 163 KB, a JVM keystore, in an image with no JVM
- `edk2/cacerts.bin` — 162 KB, **UEFI firmware certificates, in a container image**
- `pem/tls-ca-bundle.pem` — 224 KB, the one that TLS clients actually resolve

Plus `libp11-kit`, `p11-kit-client.so`, `p11-kit-trust.so`, `/usr/bin/trust` and
`/usr/bin/p11-kit` — 6.79 MB of tooling whose only job is to produce the bundles
above at build time.

### 2.4 Layer topology

Every image is a **single monolithic layer with zero sharing**. Pulling base +
python + skopeo transfers 111 MiB, which carries the same glibc userland three
times — roughly 33 MiB of pure redundancy. Chainguard moved away from
single-layer images in May 2025 and reports 70–85% less transferred data on
sequential pulls.

### 2.5 Two published claims that are false right now

- **`:latest` exists on all seven images.** `README.md` line 89 states "There is
  deliberately **no** `:latest`". It resolves to a stale digest (15.8 MiB) that
  matches neither `25.08` nor `26.08beta.3`. Tracked as #23; the branches exist
  and were never landed.
- **`static` ships full glibc.** #135 landed the honest README wording, but the
  *image* is still published under a name that promises a libc-free tier. A
  consumer reading the tag, not the README, is misled. Tracked as #116.

For a project whose entire pitch is a trustworthy supply chain, a false claim in
the README is a worse defect than four megabytes.

### 2.6 Missing runtime metadata

- No `User` in the image config — **every image runs as root by default.**
  Verified on both `base:26.08beta.3` and `python:26.08`. Google distroless and
  Chainguard both ship nonroot variants or nonroot defaults.
- No `org.opencontainers.image.base.name` / `base.digest` on any image.
- No VEX documents.
- No published rebuild-and-compare procedure, so the reproducibility argument is
  an assertion rather than something a consumer can exercise.

---

## 3. Approaches considered

### A. Race Hummingbird and Chainguard on catalog breadth — rejected

Ninety images against seven, backed by a vendor with a paid support line and a
dedicated build platform. We would lose slowly and spend everything we have doing
it. Worse, it contradicts AGENTS.md rule 3 ("don't duplicate upstream") and rule
3 of the standing decisions in #113 ("OUT: already-solved bases").

### B. Retreat to internal-only tooling — rejected

Honest, and it makes the size and breadth questions disappear. But it throws away
a real asset: we are the only distroless suite in §2.1 that no company can
rug-pull, and the demand for exactly that is rising, not falling.

### C. Sovereign floor, credibility first, then a narrow wedge — **chosen**

Three commitments, in priority order:

1. **Sovereign floor (the mandate).** Bluefin and the ghost cluster are the
   customer of record. Every image we depend on, we build. This is already the
   README's stated motivation: "Digital sovereignty isn't just for nations, this
   controls our supply chain."
2. **Credibility before growth.** No new images until the published claims are
   true and the size story is defensible. A seven-image catalog that is exactly
   what it says beats a thirty-image catalog that is approximately what it says.
3. **A wedge, not a race.** Grow only where the field has *withdrawn* rather than
   where it is strong: free, versioned, maintained images that nobody gives away
   any more. Bitnami's 28 Aug 2025 change moved its versioned catalog to
   "Bitnami Legacy" with no updates and no support. Our Wave 0 spikes —
   postgres, mariadb, valkey, nginx — are already precisely that gap.

**Positioning statement:**

> The only distroless container suite that is community-governed, reproducibly
> built, and owned by no vendor who can change the terms. Pinned to an auditable
> upstream release line, free at every version, forever.

Google can archive distroless. Chainguard gates the good tags behind a
subscription. Bitnami rug-pulled. Red Hat requires a subscription for supported
Hummingbird images. We cannot rug-pull, because there is no company here to
change its mind. That is the one axis on which we are structurally unbeatable,
and it is worth more than four megabytes.

**Hummingbird is a partner on patterns and a competitor on catalog.** We should
copy their metadata conventions — CPE labels, per-arch SBOM artifacts, VEX
semantics, builder/runtime variant split — and not chase their image count.

### D. Do nothing structural, just add images — rejected

This is the current trajectory, and §2 is what it produced: drift between what we
publish and what we claim, invisible because nothing gates it.

---

## 4. The revised catalog rule

Issue #113's rule 3 says a target is out of scope if upstream already ships on
apko/Chainguard, `gcr.io/distroless`, `ko`, or `scratch`. **Hummingbird's arrival
invalidates a literal reading of that rule** — its 90 images cover our entire
Wave 0 list, so a strict reading deletes the whole catalog plan.

The rule's *purpose* was "don't spend effort where there is no impact to win."
That purpose survives; the test needs restating:

> **A target is in scope when a maintained, free, version-pinned, distroless
> build of it is not available from a supplier who cannot revoke it.**

Applied:

| Target | Alternatives | Verdict |
| --- | --- | --- |
| postgres, mariadb, valkey | Bitnami legacy (frozen), Chainguard (paid for versions), Hummingbird (subscription for supported) | **IN** — the wedge |
| nginx | same | **IN** |
| node, python, go | Google distroless (free, versioned, maintained) | **borderline** — in only if we win on something specific |
| curl | Chainguard free `latest`, Hummingbird community | **borderline** |
| kubectl | official upstream distroless | **OUT** — AGENTS.md rule 3 |
| base, static | our own foundation | **IN** by definition |

"Maximum delta wins" from #113 stands, and the sovereignty test replaces the
supplier-name list — which is what dated so quickly.

The table governs **new** catalog additions. Images we already publish because
the sovereign floor needs them — `base`, `static`, `python`, `skopeo`,
`buildah`, `qemu-img`, `lab-runner` — stay regardless of what else exists,
because "we build what we depend on" is the mandate in §3C item 1 and is not
subject to a market test.

---

## 5. Work implied, in priority order

This section is a prioritised backlog, not a single implementation plan. It
decomposes into four plans, each independently landable: **P0 credibility**,
**P1 slimming mechanism**, **P1 gates and table-stakes metadata**, and **P2
layer sharing and catalog growth**. They should be planned in that order,
because each depends on the previous one being true.

### P0 — Truth in advertising

Cheap, entirely within our control, and it is the whole product.

1. **Delete `:latest` from all seven packages**, or delete the README claim.
   Deleting the tag is correct; the reasoning in README §Versioning is sound and
   worth keeping. (#23)
2. **Resolve `static`.** Either build a genuinely libc-free tier (targets
   ~0.7 MiB, matching Google and Chainguard, and is the largest ratio win
   available anywhere in the catalog) or unpublish the name. Shipping glibc under
   the name `static` is the single most damaging thing in the repo. (#116)
3. **Audit every factual claim in README.md and docs/skills/ against a pulled
   image**, and add that audit to the release checklist. The terminfo line in
   README §"How it works" is already stale — `include/slim.yml` deliberately
   *keeps* terminfo, with a documented reason, while the README says it is
   removed.

### P1 — Make "slim by default" true, by mechanism not by hand

The current SLIM recipe is a hand-maintained list of `rm` commands. It cannot
know what a *particular* image needs, so it is simultaneously too aggressive to
be safe and too timid to be effective. Replace the per-item guessing with one
general mechanism:

> **Unreferenced-library pruning.** Walk every ELF object in the layer, compute
> the transitive `DT_NEEDED` closure, and delete any shared object under
> `/usr/lib` that is not in it. Maintain an explicit allowlist for `dlopen`-only
> consumers (gconv modules, NSS modules, the p11-kit trust module).

This one pass removes libstdc++, libgomp, libquadmath, libmvec, readline,
ncurses, libselinux and libsepol **exactly when they are genuinely unused**, and
it does so correctly per image rather than by a global guess. BuildStream gives
us the whole graph, so we can do this rigorously where a Containerfile-based
competitor cannot. It directly answers #130 ("what generalises into `include/`")
and it is the mechanism that makes image N+1 cheaper than image N, which is the
destination in #113.

Alongside it, three unconditional removals:

4. **`/usr/lib/debug/`** — 0.95 MB of debug symbols, and it leaks BuildStream
   element names (`glibc.bst`) into published artifacts.
5. **Surplus trust-store formats** — drop the EDK2 UEFI bundle, the Java
   keystore, the objsign bundle and the `.p11-kit` source bundle; keep
   `tls-ca-bundle.pem` and the OpenSSL bundle. Verify first which path each
   runtime family resolves; `/etc/ssl` does not currently exist in the image, so
   Go finds certificates only via
   `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`. That resolution order
   must be asserted by a test before anything is deleted.
6. **Compiled locale directories** other than `C.utf8` — `en_US.utf8/LC_COLLATE`
   alone is 2.59 MB.

**Targets** (compressed, amd64):

| Image | Now | Target | Rationale |
| --- | ---: | ---: | --- |
| static | 16.4 MiB | ≤ 1.5 MiB | parity with Google and Chainguard |
| base | 17.5 MiB | ≤ 10 MiB | beats Hummingbird `core-runtime` (12 MB); within ~25% of Google `base-debian12` |
| python | 37.7 MiB | ≤ 25 MiB | parity with Chainguard |

We will not match Chainguard's 4.5 MiB glibc tier while keeping coreutils, and we
should stop implying otherwise. Keeping coreutils is a defensible product choice
— it should be stated as one, with its cost named.

### P1 — Ratchet gates, not ceilings

The reason drift is invisible is that `just verify`'s ceilings are too loose to
fire: `base` is capped at 64 MiB against ~43.9 MB actual, so 20 MB of slack has
to accumulate before anything complains. Ceilings catch catastrophes; they cannot
catch erosion.

Replace with a **ratchet**: record each image's published size, and fail the
build on any increase over the last published value beyond a small tolerance.
Growth then requires an explicit, reviewed bump — which is exactly issue #113's
standing decision 5 ("gate on regression against our own previous build").

Add content assertions next to it, so contract violations fail rather than merely
costing bytes:

- no `/usr/lib/debug/**`
- no BuildStream element names (`*.bst`) anywhere in the layer
- CA store contains exactly the formats we intend
- the existing shell and package-manager gates, unchanged

### P1 — Reach table stakes for a production image

7. **Nonroot.** `docs/skills/container-standards.md` already carries a fully
   specified non-root contract — decided in #120, UID 65532 to match
   `gcr.io/distroless`, numeric rather than named because the kubelet rejects
   named users, with the `/etc/passwd` and `--passwd=false` traps documented —
   and it is marked *"not yet implemented."* The design work is done; the images
   still run as root. This is our most conspicuous production gap and the
   cheapest one to close correctly.
8. **`org.opencontainers.image.base.name` / `base.digest`** on every derived
   image, so the FSDK lineage is machine-readable rather than prose.
9. **VEX documents.** "Zero known CVEs" is meaningless without a scanner basis, a
   clock, and machine-readable not-affected statements. Copy Hummingbird's
   CPE/name/created metadata convention rather than inventing one.
10. **A published rebuild-and-compare procedure.** BuildStream reproducibility is
    our strongest technical asset and it is currently an unexercised claim. A
    documented command that rebuilds a published digest and diffs it converts
    marketing into evidence. Note this is already a stated prerequisite in
    §9 item 9 of the factory design.
11. **A stated update policy** — rebuild on every FSDK security release, with a
    disclosed target time-to-publish for critical and high severities.

### P2 — Layer sharing

Splitting the base userland into a shared layer would save roughly 33–40 MiB
across a five-image pull, on the order of 15–20%. Real, but far less dramatic
than Chainguard's 70–85%, because our derived images are dominated by their own
payloads rather than by the shared base. Worth doing after P0 and P1; not worth
doing first, and we should not quote Chainguard's number as if it were ours.

### P2 — Catalog growth under the §4 rule

Land the wedge targets — postgres, mariadb, valkey, nginx — only once the
mechanism in P1 exists, so that each one inherits correct slimming instead of
adding another hand-maintained `rm` list.

---

## 6. What we explicitly do not do

- **No FIPS variants.** Requires a validated cryptographic module; claiming it
  without one is worse than not offering it.
- **No paid tier, no free-tier gating.** This is the entire differentiator.
  Nothing we publish is ever version-gated or subscription-gated.
- **No CVE-count marketing.** We publish a patch cadence and VEX statements.
  "Zero CVEs" without a scanner basis and a timestamp is a number, not a claim.
- **No catalog-size race.** Image count is not a success metric; it is the metric
  that would make us lose.
- **No separate package set.** Inheriting FSDK is the architecture, not a
  shortcut.

---

## 7. Success criteria

This design succeeds when all of the following hold:

1. Every factual claim in `README.md` is verifiable against a pulled image, by a
   test that runs in CI.
2. `base` is at or under 10 MiB compressed, and `static` is either genuinely
   static or gone.
3. An image cannot grow without a reviewed, explicit ratchet bump.
4. A consumer can independently rebuild a published digest and get the same
   digest, following a documented procedure.
5. Images do not run as root by default.
6. Adding catalog image N+1 requires no new hand-written slimming logic.

Note what is absent: image count, and any comparison we would lose. If we hit
these six, the sovereignty claim in §3C is backed by evidence, and that is a
claim no competitor in §2.1 can make at any price.

---

## 8. Open question for the owner

This design assumes **approach C**: sovereign floor as the mandate, the
withdrawn-free-tier gap as the growth wedge, explicitly not competing on breadth.

That was inferred, not confirmed — from README's sovereignty sentence, AGENTS.md
rule 3, #113's anti-duplication rules, and the fact that Wave 0's targets are
already exactly the Bitnami gap. If the real intent is a general public catalog
competing head-on, §4, §5 P2 and §6 all change substantially and the resourcing
question becomes the first thing to settle instead of the last.

---

## 9. Sources

- Hummingbird keynote: <https://pretalx.devconf.info/devconf-cz-2026/talk/XAJLYJ/>
- Hummingbird source: <https://gitlab.com/redhat/hummingbird/containers>
- Hummingbird announcement, 19 Nov 2025:
  <https://www.redhat.com/en/about/press-releases/red-hat-introduces-project-hummingbird-zero-cve-strategies>
- Bitnami catalog change, 28 Aug 2025:
  <https://github.com/bitnami/containers/issues/83267>
- Chainguard multi-layer change and x86-64-v2 baseline:
  <https://edu.chainguard.dev/chainguard/containers/overview/>
- Google distroless support policy:
  <https://github.com/GoogleContainerTools/distroless/blob/main/SUPPORT_POLICY.md>
- OCI annotations:
  <https://github.com/opencontainers/image-spec/blob/main/annotations.md>
- SLSA levels: <https://slsa.dev/spec/v1.0/levels>
- All size and content figures: measured 2026-08-21 from `ghcr.io`, `gcr.io` and
  `cgr.dev` OCI manifests, and from the extracted `base:26.08beta.3` amd64 layer.

# The vendor-free container factory — a systemic plan

**Date:** 2026-08-21
**Status:** awaiting owner review
**Scope:** what this repo is for, and the system that produces it. High level and
forward-looking. Not a defect list — the current images have known problems, and
this plan is about the machine that stops producing them, not about the
individual ones.

---

## 1. What we are

> **Distroless containers that are 100% free from vendors.**

Not free of charge — free *from vendors*. No company sits in the trust path, so
no company can change the terms, gate a version behind a subscription, freeze a
catalog, or archive the project. Everything is built from freedesktop-sdk
components and upstream source, on infrastructure we run, under a licence nobody
can revoke.

That is the whole product. Everything else in this document exists to make it
true at scale.

**Size is a trajectory, not a promise.** We are currently larger than Chainguard
and Google. We will stay larger for a while, and that is an acceptable price for
the property above. What is *not* acceptable is drifting the wrong way. §5 makes
improvement structural rather than aspirational: because slimming becomes a
shared mechanism instead of per-image handiwork, one improvement shrinks the
entire catalog at once.

### The starting line

Measured 2026-08-21 from live OCI manifests, compressed amd64. A baseline to
improve from, not a scorecard:

| | ours | Hummingbird | Google | Chainguard |
| --- | ---: | ---: | ---: | ---: |
| base / glibc | 16.3 MiB | 12 MB | 7.8 MiB | 4.5 MiB |
| python | 37.7 MiB | — | 18.8 MiB | 24.9 MiB |
| catalog | 7 images | 90 images | ~12 | hundreds |

---

## 2. The neighbours

**Red Hat Project Hummingbird** — Stef Walter and Valentin Rothberg, DevConf.CZ
2026, *"How I learned to stop worrying and love CVEs."* Its argument is that
~50,000 CVEs a year makes manual assessment and backporting unscalable, so the
answer is to track upstream closely, automate the entire supply chain, and ship
zero *known* CVEs at publication. **We agree with all of it.** They build their
own RPM universe from Fedora specs; we inherit FSDK and maintain no package set
at all.

They are a **partner on patterns** — per-architecture SBOM artifacts, CPE
metadata for VEX matching, builder/runtime variant separation, automated upstream
tracking. We should copy these conventions rather than invent our own.

They are a **competitor on catalog**, and we will not win that race: 90 images
and 254 variants, backed by a support organisation. We should not try. Supported
Hummingbird images require a Red Hat subscription, which is precisely the
property §1 rejects, and that difference matters more than image count ever will.

Google distroless is small and well made but narrow, and Google archives things.
Chainguard is excellent and gates versioned images behind a subscription. Every
one of them is a vendor.

---

## 3. The antipattern we reject

The opinionated application-wrapper image — the Bitnami style — is **not a model
for this repo**. Concretely, we do not build:

- shell entrypoints or `docker-entrypoint.sh` init scripts
- configuration templating, environment-variable config rendering, `envsubst`
  layers
- vendor-prefixed filesystem layouts (`/opt/<vendor>/...`)
- "helper" userland added so an operator can poke around inside
- images whose contract is a set of environment variables rather than a program

That style trades a package manager for a shell and a pile of bespoke glue, then
couples the image to a chart. It is the opposite of distroless, it makes every
image a snowflake, and its collapse in 2025 demonstrated exactly the vendor
dependency §1 rejects.

**Our contract is narrower and duller:** an image is the runtime closure of one
program, plus the data that program needs, plus metadata. Configuration is the
deployment's job. If an image needs a shell to start, we built the wrong thing.

`lab-runner` remains the one documented, scoped exception. It is a tool for our
own CI, not a product pattern, and nothing else may cite it as precedent.

---

## 4. The actual problem: marginal cost

The reason this repo has seven images and not seventy is not ambition. It is that
**image N+1 costs about the same as image N.** Every image today requires a human
to hand-author four separate things:

1. **Component selection** — which FSDK `components/*` the program needs.
2. **Slimming** — a bespoke list of `rm` commands guessing at what is unused.
3. **Verification** — a size ceiling and a smoke test, hand-written into the
   `Justfile`'s per-image case statement.
4. **Metadata** — description, labels, manifest entry.

Only the first genuinely requires judgement. The other three are *derivable*, and
today they are not derived. That is the systemic defect, and it is the one worth
fixing, because it sits upstream of everything else — including size, which is
currently a per-image guessing game and ought to be a property of the system.

Issue #113 already named the destination: *"the 2nd image is half the work of the
1st, the 3rd half of that, and the 250th is a config entry."* This plan is how
that becomes real.

---

## 5. The system: declare the image, derive everything else

One declarative record per image is the **only** thing a human writes. Elements,
slimming, gates, smoke tests, labels and SBOM wiring are all generated or derived
from it.

```yaml
# catalog/nginx.yaml — illustrative shape, not the final schema
name: nginx
kind: runtime                  # runtime | toolchain | utility | shell-enabled
entrypoint: /usr/sbin/nginx
provides: [/usr/sbin/nginx]    # must exist, must execute
components: [nginx]            # FSDK components, or an upstream-source element
data: [mime-types]             # non-ELF payload the program genuinely needs
smoke: ["-v"]                  # how the image proves it works
```

Five mechanisms turn that record into a published image. Each is written once and
serves the whole catalog.

### 5.1 Generated element graph

The `stack → compose → script` pipeline is already uniform across every image;
what varies is only the dependency list and the exclude set. Generate the three
`.bst` files from the record, commit the output, and add a CI check that
regenerated output matches what is committed — the same drift-check pattern as
`go generate`. Committed generated files stay reviewable and keep BuildStream's
caching behaviour legible.

### 5.2 Dependency-closure pruning — the key lever

Replace hand-authored `rm` lists with one general mechanism:

> Walk every ELF object reachable from the declared `provides`, compute the
> transitive `DT_NEEDED` closure, and delete every shared object not in it.
> Maintain an explicit allowlist for `dlopen`-only consumers — gconv modules,
> NSS modules, PKCS#11 modules.

This is the difference between guessing and knowing. It is correct *per image*
rather than globally, it needs no maintenance when FSDK changes, and it removes
whole categories at once.

The current `base` illustrates the scale: it carries 6.8 MB of p11-kit machinery
whose only job is generating CA bundles at build time, plus C++ and OpenMP
runtimes in an image containing no C++ program. No shared `rm` list can safely
remove those, because some *other* image in the catalog genuinely needs them. A
closure computed per image can.

BuildStream hands us the complete dependency graph, so we can do this rigorously
where a Containerfile-based competitor cannot. **This is our strongest technical
differentiator and it is currently unexploited.**

It also answers #130 directly: the per-runtime-family bloat-stripping recipes
generalise into *one* mechanism rather than into a family of lists.

### 5.3 Derived verification

`just verify` currently hard-codes a per-image case statement of size ceilings and
smoke tests, so adding an image means editing it. Derive instead:

- **gates** from `kind` — `runtime` and `toolchain` get the full distroless gate
  set, `shell-enabled` the reduced set
- **smoke test** from `provides` + `smoke` — execute the declared binary with the
  declared arguments
- **content assertions** applied uniformly: no shell, no package manager, no
  debug symbols, no build-system artifacts or element names leaked into the
  layer, trust store limited to the formats we intend

No per-image verification code. A new image inherits the entire contract.

### 5.4 The size ratchet

No human picks a size number. Record each image's published size; fail on any
increase beyond a small tolerance. Growth requires an explicit, reviewed bump.

This is what makes §1's "we improve over time" structural: the ratchet forbids
regression, and §5.2 delivers improvement across every image simultaneously. Size
stops being a target somebody has to defend and becomes a monotonic property of
the system. It is also #113's standing decision 5, finally implemented.

### 5.5 Uniform provenance

Generate from the record plus the FSDK ref, for every image without exception:
OCI annotations including `base.name` and `base.digest`, per-architecture SPDX
SBOMs, cosign signatures, build provenance, a non-root `User`, and VEX documents.

Two of these are forward commitments rather than housekeeping:

- **Non-root by default.** `docs/skills/container-standards.md` already carries a
  complete non-root contract from #120 — UID 65532, numeric because the kubelet
  rejects named users, with the `/etc/passwd` and `--passwd=false` traps
  documented — marked *"not yet implemented."* The design is done; the images
  still run as root.
- **A published rebuild-and-compare procedure.** BuildStream reproducibility is
  the technical foundation of the vendor-freedom claim, and it is currently an
  assertion nobody can exercise. A documented command that rebuilds a published
  digest and diffs it turns the claim into evidence. Without it, "you don't have
  to trust a vendor" only means "trust us instead."

---

## 6. What goes in the catalog

The selection rule follows from §1, not from what any vendor is doing. Issue
#113's original rule listed supplier names, and dated within a year when
Hummingbird shipped 90 images.

> **A target is in scope if we or our ecosystem depend on it, and we can build it
> entirely from FSDK components and upstream source with no vendor in the trust
> path.**

In priority order:

1. **What we run.** Anything the Bluefin and ghost infrastructure depends on. We
   build what we depend on — the mandate, not a market judgement, and never
   subject to a "does someone else already ship it" test.
2. **What our ecosystem runs.** Widely deployed workloads Bluefin and bootc users
   actually deploy, where no vendor-free option exists.
3. **Nothing else.** Image count is not a goal. An image we cannot keep current is
   worse than an image we never shipped, because it ages silently in someone
   else's cluster.

Two standing rules survive unchanged: **maximum delta wins** — given a choice,
carve from the fattest upstream base — and **don't duplicate upstream** — if a
project already ships a genuinely distroless, vendor-free build, consume it.

---

## 7. Phases

Each phase is independently landable and leaves the repo better than it found it.

**Phase 0 — Make the published claims true.** Small, unglamorous, the price of
admission. A supply-chain project whose README does not match its registry has no
product. Bounded work on the `:latest` tag, the `static` tier, and the README's
factual claims, plus a release-checklist step so it cannot recur.

**Phase 1 — Declare.** Introduce the catalog record and backfill all seven
existing images into it. No behaviour change, nothing generated yet. The
deliverable is proof the schema describes reality, including the awkward cases —
`lab-runner` and the nspawn machine image.

**Phase 2 — Derive.** Generate the element graph and the verification contract
from the record; delete the hand-written per-image logic in the `Justfile` and
`elements/`. **This is the phase that changes the economics.** Acceptance test:
add a trivial image and touch exactly one file.

**Phase 3 — Prune.** Land dependency-closure pruning as the shared mechanism and
retire the hand-authored `rm` lists. Expect a catalog-wide size drop from a single
change. Publish the before/after for every image — that number is the proof that
§1's "we improve over time" is a mechanism rather than a hope.

**Phase 4 — Contract.** Ratchet, content assertions, non-root, `base.name` /
`base.digest`, VEX, and the rebuild-and-compare procedure. After this phase a
stranger can verify the vendor-freedom claim without our help.

**Phase 5 — Scale.** Add images under §6, each measured against the Phase 2
acceptance test. If an image costs more than a record plus review, that is a bug
in the system, and the fix belongs in the system rather than in the image.

Phases 0 and 1 can run in parallel. Phase 3 depends on 2; Phase 5 depends on
everything.

---

## 8. Success criteria

1. **Adding an image touches one file.** The headline metric, and the one that
   makes everything else possible.
2. **Slimming is a mechanism, not a list.** No image carries bespoke removal
   logic, and improving the mechanism improves every image at once.
3. **No image can grow silently.** Size moves monotonically down, by ratchet.
4. **A stranger can verify the vendor-freedom claim** by rebuilding a published
   digest and getting the same digest.
5. **Every published claim is checked by a test**, not by a reviewer's memory.
6. **Nothing we publish is ever gated** — no paid tier, no version gating, no
   subscription, no rug-pull, ever.

Deliberately absent: image count, and any size comparison against a vendor. We
are not trying to win those.

---

## 9. Non-goals

- **No app-wrapper images.** §3. No shell entrypoints, no config templating, no
  vendor prefixes.
- **No catalog-size race.** Breadth without currency is a liability.
- **No FIPS variants** without an actually validated cryptographic module.
- **No CVE-count marketing.** We publish a patch cadence and VEX statements.
  "Zero CVEs" without a scanner basis and a timestamp is a number, not a claim.
- **No separate package set.** Inheriting FSDK is the architecture. The moment we
  maintain our own packages, we have become a small, underfunded distribution.
- **No size gate that blocks useful work.** The ratchet prevents regression; it
  does not demand parity with anyone.

---

## 10. Sources

- Hummingbird keynote: <https://pretalx.devconf.info/devconf-cz-2026/talk/XAJLYJ/>
- Hummingbird source: <https://gitlab.com/redhat/hummingbird/containers>
- Chainguard versioned-image and baseline policy:
  <https://edu.chainguard.dev/chainguard/containers/overview/>
- Google distroless support policy:
  <https://github.com/GoogleContainerTools/distroless/blob/main/SUPPORT_POLICY.md>
- OCI annotations:
  <https://github.com/opencontainers/image-spec/blob/main/annotations.md>
- Repo context: #113 (catalog map and standing decisions), #120 (non-root
  contract), #130 (what generalises into `include/`), #146 (Wave 0 spikes).
- Size figures measured 2026-08-21 from `ghcr.io`, `gcr.io` and `cgr.dev` OCI
  manifests.

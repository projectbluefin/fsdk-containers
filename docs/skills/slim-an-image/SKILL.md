---
name: slim-an-image
version: "1.3"
last_updated: "2026-09-18"
id: slim-an-image
one_line_purpose: Shrink an OCI image by extending the shared SLIM recipe and proving the removal.
entry_point: docs/skills/slim-an-image/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [slim, size, distroless, optimization, split-rules]
description: "The SLIM recipe — what to strip from an FSDK-carved image, the size levers, and their risk tiers. Use when shrinking an image or extending the shared slim block."
metadata:
  type: procedure
  context7-sources:
    - /apache/buildstream
    - /argoproj/argo-workflows
---

# Slim an Image

Use when an image is too large, or when extending the shared SLIM recipe.

## When to Use

Use when carving a smaller OCI image from FSDK, removing runtime bloat, or
adding a regression assertion for removed content.

## When NOT to Use

Do not use for the shell-enabled nspawn machine-image lane; its retained
development environment is deliberate. Do not replace a component-based image
with a package-manager overlay.

## Core Process

1. Measure the artifact and identify the largest removable runtime content.
2. Reuse `include/slim.yml`; apply only the documented exception when required.
3. Build the affected image and run its `just verify` contract.
4. Add an assertion or executable smoke test for behavior that a removal or
   stripping step could regress.

Rule: include `include/slim.yml` in every new OCI script and choose the
appropriate shared command variable; do not copy/paste the recipe.

```
rm -rf _sizecheck
just bst artifact checkout <name>/<name>-runtime.bst --directory _sizecheck
du -sh _sizecheck && du -ah _sizecheck/usr | sort -rh | head -20
rm -rf _sizecheck
```

`_sizecheck` must be a project-relative path — the bst container only sees `/src`
(the repo). An absolute `/tmp/...` path is written inside the container and lost.

## Reference files

| Reference | What is in it |
| --- | --- |
| [`references/os-layer-recipe.md`](references/os-layer-recipe.md) | Why the recipe is manual, the split-domain leak trap, why every image (even an intended-static one) must run it, the risk tiers of what to cut, and the no-`find` sandbox constraint. |
| [`references/runtime-family-recipes.md`](references/runtime-family-recipes.md) | The payload layer: the per-family strip/keep table (JVM, Python, Node, Go, C daemons), the implemented Python recipe, where `include/slim-<family>.yml` fragments live, smoke-test and measurement methodology, and the open zstd decision. |
| [`references/prebuilt-binaries.md`](references/prebuilt-binaries.md) | Stripping vendored upstream binaries: measured Argo/kubectl numbers, `strip-binaries: ""` plus the binutils build dep, and the `just verify` execution checks. |

## Lock it in

Add a regression assertion to `just verify` (the slim gates) for anything you
cut that must stay gone, so it fails the build if it creeps back.

## Common Rationalizations

- “The binary ran once locally.” A one-time check does not protect the next
  version bump; put the check in `just verify`.
- “Excluding `shells` removes bash.” Bash is in FSDK's runtime domain and must
  be explicitly removed for distroless images.
- “Excluding `debug` removes the debug symbols.” It did not — ~905 KB of separated
  DWARF survived it until #316 stripped it in `include/slim.yml` and gated it. Verify the rootfs, not the element.
- “The `compose exclude:` list says it is gone, so it is gone.” Two domains have now
  been caught leaking. Confirm with `podman export | tar -tvf`.
- “The build dependency is harmless.” Confirm it is build-only and absent from
  the composed runtime image.

## Red Flags

- Copying a SLIM command block instead of including `include/slim.yml`.
- Removing CA certificates, tzdata, or required charset modules to hit a size
  target.
- Stripping a prebuilt binary without a local-only execution test.

## Verification

- [ ] The element uses the component minimum, never `platform.bst`.
- [ ] `just validate`, the affected image build, and `just verify` pass.
- [ ] The image retains CA certificates, tzdata, and the required charset set.
- [ ] New stripping or removal behavior has a durable `just verify` regression
  check.

## Reference result

`base`: ~73 MB rootfs → **~45 MB image** after slim (measured with
`podman image inspect .Size`), all gates green.

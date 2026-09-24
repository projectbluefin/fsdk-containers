---
name: add-new-image
version: "1.2"
last_updated: 2026-09-24
id: add-new-image
one_line_purpose: Add a distroless OCI image by declaring one catalog record.
entry_point: docs/skills/add-new-image.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [buildstream, oci, distroless, images]
description: "Add a new distroless image by declaring one catalog record and generating its BuildStream elements."
metadata:
  type: procedure
---

# Add a New Distroless Image

Use when adding a new runtime/tool image carved from FSDK.

## When NOT to Use

- The tool already ships an official, maintained CNCF/upstream distroless image
  (e.g. `kubectl`). Consume that upstream image instead.
- You only need to shrink an existing image → `slim-an-image/SKILL.md`.

## Adding an image

1. Write `catalog/<name>.yaml`. That is the image definition.
2. Add `<name>` to `oci_images` and `image_paths` in `elements/targets.json`
   (the `image_paths` entry owns `elements/oci/<name>.bst`, `elements/<name>/`,
   and `catalog/<name>.yaml`, so a record-only change still gates a build).
   Then add every in-repo component directory the record builds from — see
   [Own the directories your image builds from](#own-the-directories-your-image-builds-from).
3. Run `just catalog-write` to generate the three BuildStream elements.
4. Run `BUILD_IMAGE_NAME=<name> just build && BUILD_IMAGE_NAME=<name> just verify`.
5. Commit the record, the targets.json entry, and the generated elements together.

**Never hand-edit a generated element.** Exactly these three paths are generated
from the record and carry a DO-NOT-EDIT header naming it:
`elements/<name>/<name>-stack.bst`, `elements/<name>/<name>-runtime.bst`, and
`elements/oci/<name>.bst`. Other elements in those directories, including init
scripts and similar support elements, are hand-authored and are not generated.
A hand edit to a generated path is reverted by the next `just catalog-write`
and fails the `image-catalog` pull-request gate in the meantime. Change the
record.

If the image needs something the record cannot express, that is a gap in
`catalog/schema.json`. Extend the schema and the generator so the next image
gets it for free — do not work around it with a bespoke element.

## Own the directories your image builds from

The three generated paths are not the whole ownership story. `image_paths` is
what `just changed-targets` matches a pull request's diff against, so it must
also list every **in-repo component directory** the image builds from — any
`stack.depends` entry that is a local element path rather than a
`freedesktop-sdk.bst:` junction reference, plus anything that element depends
on in turn.

Walk `stack.depends` in the record, and for each entry without a
`<junction>.bst:` prefix, add `elements/<dir>/` to the image's `image_paths`
list. `review-runtime` is the worked example: it depends on
`node/node-stack.bst`, which depends on `node/node.bst`, so its entry carries a
fourth path, `elements/node/`:

```json
"review-runtime": ["elements/oci/review-runtime.bst", "elements/review-runtime/",
                   "catalog/review-runtime.yaml", "elements/node/"]
```

Omitting it fails *open*, silently: a change under `elements/node/` matches no
image, `changed-targets` returns an empty matrix, `pr-build-oci` skips, and the
pull request goes green having built nothing. That is exactly how a broken
`node.bst` reached `main` unnoticed. Junction references need no entry — the
junction itself is covered by `shared_paths`, which selects the canary image.

A directory shared by two images belongs in both lists; `image_paths` prefixes
overlapping is only forbidden between *published* images' own paths, which
`tests/test_catalog_conformance.py::test_no_image_owns_another_images_paths`
checks. A component directory that is not in `oci_images` is not an image's own
path, so listing it more than once is fine.

## Catalog conventions

- `stack.depends` is an ordered list. Its order is load-bearing because it
  changes the BuildStream cache key; transcribe the committed element verbatim.
- `keywords` is transcribed per image. The
  `io.artifacthub.package.keywords` label varies across images (and
  `lab-runner` omits `distroless`); do not derive it.
- `export_description` is the published `org.opencontainers.image.description`
  that `just export` applies to the squashed image. It defaults to
  `description`; set it only when the published string must differ from the
  element-level one. It is never rendered into a BuildStream element, so it
  cannot move a cache key.
- Descriptions, entrypoints, and keywords are interpolated into single-quoted
  YAML scalars by the generator, which escapes `'` as `''`. Apostrophes are
  safe; do not pre-quote or pre-escape values in the record.
- Smoke `args` and `entrypoint_override` may contain spaces or glob characters:
  `scripts/verify_contract.py` emits them newline-delimited and the `verify`
  recipe reads them with `mapfile` into bash arrays, so every argument reaches
  `podman run` as exactly one argument.

## Element reachability and the spike registry

Every `.bst` file under `elements/` must be reachable from a published target,
or be declared inert. `tests/test_catalog_element_reachability.py` walks
`depends:`/`build-depends:` from the publication roots — the `oci_images` in
`elements/targets.json`, the nspawn machine image, the podman VM guest, and the
`project.conf` junctions — and fails on anything it cannot reach.

Inert elements are registered in that module's `SPIKE_ELEMENTS` dict, keyed by
path relative to `elements/`, valued with the issue that tracks the spike. The
registry is asserted in both directions: an unregistered orphan fails, and so
does a registry entry whose file is gone or has since become reachable.

**The contract: a spike graduating must leave the registry in the same PR that
wires it into a published target.** Adding `<name>` to `oci_images`, or
depending on a spike element from an existing image's stack, makes those files
reachable; leave them in `SPIKE_ELEMENTS` and the gate goes red.

Graduation is per *file*, not per directory. A spike directory can graduate
partway: `review-runtime` depends on `node/node-stack.bst`, so that file and
`node/node.bst` left the registry, while `node/node-runtime.bst` — the
distroless chisel for a standalone `oci/node.bst` that does not exist yet — is
still inert and still registered. Remove exactly the files your change wired in.

If you add a publication lane that is not an OCI image in `targets.json`, add
its root element to the hardcoded root set in that module's `setUpClass`.
Otherwise every element reachable only from it reads as a false orphan.

## Prerequisites

Check that the required FSDK component exists before writing the record:

```bash
just bst show freedesktop-sdk.bst:components/python3.bst
```

If the component is absent, follow the separate packaging workflow rather than
inventing a bespoke image element.

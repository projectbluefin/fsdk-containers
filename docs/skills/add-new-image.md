---
name: add-new-image
version: "1.0"
last_updated: 2026-08-21
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
- You only need to shrink an existing image → `slim-an-image.md`.

## Adding an image

1. Write `catalog/<name>.yaml`. That is the image definition.
2. Add `<name>` to `oci_images` and `image_paths` in `elements/targets.json`.
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

## Catalog conventions

- `stack.depends` is an ordered list. Its order is load-bearing because it
  changes the BuildStream cache key; transcribe the committed element verbatim.
- `keywords` is transcribed per image. The
  `io.artifacthub.package.keywords` label varies across images (and
  `lab-runner` omits `distroless`); do not derive it.

## Prerequisites

Check that the required FSDK component exists before writing the record:

```bash
just bst show freedesktop-sdk.bst:components/python3.bst
```

If the component is absent, follow the separate packaging workflow rather than
inventing a bespoke image element.

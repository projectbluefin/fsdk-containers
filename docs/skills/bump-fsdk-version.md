---
name: bump-fsdk-version
description: Move fsdk-containers to a new freedesktop-sdk release and refresh the derived tags. Use when tracking the FSDK lifecycle or pinning a new FSDK point release.
metadata:
  context7-sources:
    - /apache/buildstream
---

# Bump the FSDK Version

Use when moving to a new FSDK release, or refreshing the pinned ref.

## The version model

There is no application version for these images — the version axis IS the FSDK
release. Tags are derived from the pinned junction ref in
`elements/freedesktop-sdk.bst` (the `ref:` line, e.g.
`freedesktop-sdk-25.08.13-...`):

- `:latest` — rolling, every publish
- `:25.08` — FSDK minor line (moves within the line)
- `:25.08.13` — FSDK point release, treated **immutable**

`just tags` parses these from the ref. Provenance labels
`io.projectbluefin.fsdk.version` / `io.projectbluefin.fsdk.ref` are applied at
export so every image self-declares its base.

## Procedure

1. Find the target ref/tag upstream:
   <https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/releases>
   (or the `freedesktop-sdk-YY.MM` branch tip for a minor line).

2. Update the `ref:` in `elements/freedesktop-sdk.bst` to the new tag/commit.

3. Re-check patches still apply — FSDK ships local patches under
   `patches/freedesktop-sdk/`. If a release changed the patched files, refresh or
   drop them. `just validate` surfaces patch failures.

4. Rebuild and verify:

   ```
   just validate
   just tags        # confirm derived tags look right
   just build
   just verify
   ```

5. Follow the FSDK **lifecycle**: track the active minor line; when FSDK EOLs a
   line, move `:latest` to the next supported minor. Don't pin to an EOL line.

## Gotchas

- Bumping across a minor line (e.g. 25.08 → 26.08) may rename/relocate components.
  Re-confirm `components/*` names against the staged junction before assuming a
  dep still exists.
- A point-release tag is immutable: once `:25.08.13` is published, never republish
  different bits under it.

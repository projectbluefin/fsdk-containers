# Patch Queue Policy and Overrides

Reference for [`../SKILL.md`](../SKILL.md) — what a junction patch queue actually
does to the cache key, the order patches apply in, and how to remove a
junction-provided component without patching it.

## Correcting the inherited rule

Dakota's `patch-junctions.md` states, in a fenced block, `NO LOCAL JUNCTION PATCH
QUEUES`, and claims all junction patches were removed. **That rule as written is
false, and copying it here would be actively harmful.** Evidence:

- `dakota/patches/freedesktop-sdk/` currently holds **7** patches.
- Dakota's own `bst-overrides.md` states the opposite and correct nuance: the queue
  "must stay byte-identical to GBM's `patches/freedesktop-sdk/` directory at the
  pinned GBM commit", enforced in CI by `just patch-drift-check`.
- This repo carries a `patch_queue` on its FSDK junction too, and
  `elements/gnome-build-meta.bst` documents why in an inline comment:
  *"This along with the patches is required and has to match what gnome-build-meta
  is using."*

**The real principle:** a junction's patch queue is part of its cache key, so the
queue selects *which upstream artifact cache you can reuse*.

- Patches that **diverge** from what your upstream parent pins are cache-destroying.
  That is the thing to prohibit.
- Patches that **replicate** the parent's queue byte-for-byte are cache-*aligning*,
  and are mandatory rather than forbidden.

The enforceable rule is **drift control against the parent's queue at the pinned
ref** — not "never patch a junction". Deleting this repo's FSDK junction patches
because a doc said "no patch queues" would move it *further* from GBM, not closer.

## Patch queue mechanics

Patches apply in **alphabetical filename order**. Numbering gaps are intentional —
they leave room to insert without renaming. To insert between `0004` and `0005`, name
it `0004b-...`; do not renumber the tail to make the sequence look tidy.

## Void-override pattern

To remove a junction-provided component entirely rather than patch it, override it to
an empty `kind: stack` element — the same pattern GBM uses for `void/zenity.bst`:

```yaml
# elements/freedesktop-sdk.bst
config:
  overrides:
    components/<unwanted>.bst: <local-void-element>.bst
```

Cache impact check before committing: if everything downstream of the element is
already uncached, the void override is cache-neutral. Compare `just bst show` state
counts before and after.

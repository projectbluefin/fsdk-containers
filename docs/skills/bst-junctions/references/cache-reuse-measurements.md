# Cache Reuse: Measurements and Open Leads

Reference for [`../SKILL.md`](../SKILL.md) — what was actually measured about
artifact-cache reuse in this repo, what is still only a hypothesis, and the commands
that re-derive every number below.

Everything in this file is a **dated snapshot**. The junction pins and patch queues
move; do not quote a value from here without re-deriving it first.

## Re-deriving the current values

```bash
grep -n 'ref:' elements/freedesktop-sdk.bst    # our FSDK pin
grep -n 'ref:' elements/gnome-build-meta.bst   # our GBM pin
ls patches/freedesktop-sdk/                    # our FSDK patch queue
ls patches/gnome-build-meta/                   # our GBM patch queue
grep -n 'patch_queue' elements/*.bst           # which junctions carry a queue
grep -rn 'x86_64_v3' project.conf elements/    # prose reminders only — the option is
                                               # never defined (AGENTS.md ban)
grep -n 'gbm.gnome.org\|cache.projectbluefin.io' project.conf   # configured caches
```

For the GBM side of the comparison, check out GBM at the ref printed by the second
command and list its `patches/freedesktop-sdk/` and its FSDK junction `ref:`.

## Measured 2026-08-09: this repo did not reuse GBM's cache

`project.conf` lists `https://gbm.gnome.org:11003` as an artifact and source cache,
which implies the intent is to reuse GNOME's FSDK artifacts. **Measured 2026-08-09,
that reuse could not have been happening**, for three independent reasons.

Historical snapshot — re-derive with the commands above before acting on it:

| | This repo (2026-08-09) | GBM at the then-pinned GBM ref (`cc8cb59`) |
|---|---|---|
| FSDK `ref:` | an FSDK 26.08 beta pre-release | `freedesktop-sdk-25.08.13` |
| `patches/freedesktop-sdk/` | 2 patches (`0001`, `0002`) | 7 patches (`0001`–`0007`) |
| `x86_64_v3` option | not defined (banned by AGENTS.md) | set via `(?)` in the junction |

Any **one** of these makes our FSDK junction key differ from GBM's; all three did.
So every FSDK-derived element must come from `cache.projectbluefin.io` or be compiled
locally — `gbm.gnome.org` contributed nothing at that pin.

**This is not automatically a bug.** Two of the three divergences are deliberate: the
`x86_64_v3` ban is a hard rule, and the FSDK line is a live decision (#125/#126). But
it should be a *chosen* trade-off, not an accident, and the `x86_64_v3` divergence
alone may be sufficient to make GBM reuse permanently impossible — in which case the
`gbm.gnome.org` cache entry is decoration and the patch queue is cargo cult.

**Unverified / open:** whether pinning FSDK to exactly GBM's ref *and* matching all 7
patches would actually restore reuse, given the `x86_64_v3` option difference. Nobody
has measured a before/after cache-hit rate here. Do not assert a number until someone
does. For scale, dakota measured that removing a single divergent junction patch
restored **1053 of 1090** elements from cache (96%) — so the effect size is large
enough to be worth measuring properly.

## Open lead: this repo's GBM junction still carries a patch queue

Dakota removed the patch queue from its `gnome-build-meta` junction and measured
**1053 of 1090 elements (96%)** restored from cache. **This repo still carries
that queue.** Verified 2026-08-09 — confirm it is still true with
`grep -n 'patch_queue' elements/gnome-build-meta.bst`:

| | dakota | fsdk-containers |
|---|---|---|
| `elements/gnome-build-meta.bst` | no `patch_queue` (clean) | `patch_queue` -> `patches/gnome-build-meta` |
| `patches/gnome-build-meta/` | directory does not exist | `disable-lorry-mirrors.patch` |

It is the *same patch* dakota dropped.

**Do not blindly delete it, and do not expect dakota's 96%.** The blast radius
here is different: dakota imported its whole graph through GBM (WebKit included),
whereas this repo uses GBM only for the `collect_initial_scripts` plugin and the
FSDK override (see `project.conf`). The effect could be large or nearly nil.

**Unverified — this is a hypothesis, not a finding.** What would settle it:
compare `just bst show` cached/waiting state counts across the graph with the
queue present vs removed, on the same FSDK pin. Until someone does that, quote
no number. See also the `gbm.gnome.org` reuse table above — the FSDK junction
diverges for three independent reasons, so fixing only the GBM queue may change
nothing on its own.

# BuildStream Remote Execution — Worker File-Pool Integrity

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

## Data-integrity failure: a build element corrupted the worker file pool

**Symptom.** A build fails parsing a file that should be empty. The canonical
case is Python: `compression/__init__.py` ships as a zero-byte file, but stages
as 23 bytes containing `linuxbrew:100000:65536` (an `/etc/subuid` line), so
`import` dies with a `SyntaxError`. The failing image has nothing to do with
brew, and the same string turning up in an unrelated stdlib file is the
fingerprint.

**Mechanism.** `bb_worker` materialises an action's input root by **hardlinking**
out of a persistent file pool (`worker.jsonnet`: `buildDirectories[0].native`,
`cacheDirectoryPath: /worker/cache`, backed by a **hostPath**, so it survives
pod restart *and* pod deletion). `runner.jsonnet` sets `runCommandsAs: {userId: 0}`
with `chrootIntoInputRoot`, and root ignores the read-only bit. So a build
command that writes **in place** over a staged file rewrites the shared inode:

```sh
echo 'linuxbrew:100000:65536' > "$L/etc/subuid"   # FSDK ships this file EMPTY
```

FSDK's `/etc/subuid` is zero bytes, so that single redirect stored 23 bytes
under the **empty-file digest** — and every zero-byte file staged on that worker
afterwards came back as those 23 bytes. One element, in one image, silently
corrupts every build on the node.

Truncation is the same hazard: `: > "$L/etc/machine-id"` stores zero bytes under
whatever digest machine-id had.

**The rule.** In any element that writes into a **staged** tree (`/layer` in the
oci-builder elements — *not* `%{install-root}`, which starts empty), never
redirect onto a path that may already exist. `rm -f` first, or write to a temp
file and `mv` — `rename()` swaps the directory entry and leaves the pool inode
alone. `rm` itself is safe: it unlinks.

**Diagnosis — find mutated pool entries directly.** Pool entries are named
`1-<digest>-<size>{-,+}x`, so an entry whose on-disk size disagrees with the
size encoded in its own name has been written in place:

```bash
export KUBECONFIG=~/.kube/bluespeed.yaml
for w in worker-fsgmc worker-n8z6v; do
  kubectl exec -n buildbarn $w -c runner -- sh -c \
    'cd /worker/cache && ls -l | awk "{n=\$NF; sz=\$5; split(n,a,\"-\"); if (a[3]!=\"\" && sz+0 != a[3]+0) print sz, n}"'
done
```

Any output means worker-side pool corruption.

**Do NOT wipe the `cas`/`ac` PVCs for this.** It destroys cache shared with
dakota, kills in-flight builds, and fixes nothing — the pool is node-local
hostPath state. (Both CAS PVCs were recreated during this incident and the
symptom persisted, which is what exonerated the CAS.)

**Cluster-side recovery is lab-owned, not ours.** The worker pool is configured
by `manifests/buildbarn-worker.yaml` in `projectbluefin/lab`; that repo's
`docs/skills/cluster-tooling/buildstream.md` already forbids node-local
`hostPath` caches. Do not perform worker surgery from this repo — report it.
Tracking: [projectbluefin/lab#637](https://github.com/projectbluefin/lab/issues/637).

**Structural note.** The hardlink pool assumes actions never modify their
inputs; chroot-as-root breaks that by construction. The virtual/FUSE build
directory is the real mitigation, and `worker.jsonnet` records that the FUSE
experiment failed and the workers must stay on native directories — so until
that is revisited, the discipline above is the only guard.

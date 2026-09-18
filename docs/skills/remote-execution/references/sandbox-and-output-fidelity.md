# BuildStream Remote Execution — Sandbox and Output Fidelity

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

## What remote execution does not preserve

**File ownership and permission bits do not survive the grid.** The REAPI
captures an action's output tree as content plus a minimal executable bit, so
`chown` and `chmod` run inside a build element are silently lost — a directory
created `0700` and owned `65532:65532` comes back `0755` and root-owned. There
is no error; the element builds green and the wrong thing ships.

This was measured on `postgres` (PGDATA) and applies to every element:

```yaml
# Does NOT work in a build element on the grid:
install-commands:
  - mkdir -p "%{install-root}/var/lib/postgresql/data"
  - chmod 0700 "%{install-root}/var/lib/postgresql/data"   # lost
  - chown 65532:65532 "%{install-root}/..."                # lost
```

Build elements may only create the *scaffold* (the `mkdir`). Anything that
depends on ownership or mode — the data-directory permissions a server refuses
to start without, and the `/etc/passwd` + `/etc/group` entries the non-root
contract requires — belongs in the **OCI script stage**, which runs in-sandbox
when the layer is assembled, not on the grid.

The same constraint explains why `/home/nonroot` ships root-owned: the
BuildStream sandbox cannot `chown` to a UID. Workloads needing a writable home
or data directory mount a volume, which is the Kubernetes-idiomatic answer
anyway.

# Upstream-First Override Policy

Reference for [`../SKILL.md`](../SKILL.md) — the escalation ladder before you carry a
local patch, the exit condition every override must have, and the standing ban on
local toolchain workarounds.

## Upstream-first

Local overrides are maintenance debt. The order of preference is always:

1. **Check whether upstream already fixed it** → bump the junction ref.
2. **Fix it upstream** → submit the patch, reference the MR.
3. **Override locally, last resort** → only with a documented exit condition.

| Question | If yes → |
|---|---|
| Is the fix in upstream's latest ref? | Bump the ref instead |
| Will upstream accept it this cycle? | Submit upstream; carry a temporary patch with `Upstream-Status: Submitted <URL>` |
| Is this genuinely repo-specific? | Local override is justified — document why |
| Is it a security backport? | Justified — link the CVE and the upstream fix |

Every patch and override needs an exit condition, written down:

```
Upstream-Status: Submitted https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/merge_requests/NNN
Exit condition: Drop after FSDK ships <release>
Exit condition: Permanent — repo-specific, not upstreamable
```

Without one it becomes permanent debt with no path to removal.

## No local toolchain workarounds

If a dependency fails to build under the baseline toolchain, **do not** compile a local
GCC, ship a bootstrap toolchain, or add compiler-specific hacks. Align to an upstream
ref that works instead. In dakota this was learned expensively: local compiler
workarounds on the junction invalidated the whole imported graph and forced the runners
to rebuild glibc, systemd and the compiler itself, producing OOMs and multi-hour builds.

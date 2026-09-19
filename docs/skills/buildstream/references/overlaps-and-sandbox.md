# BuildStream — Overlaps and Remote-Sandbox Constraints

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

## Overlaps

When your element installs a file that an FSDK junction component also provides,
BuildStream raises an overlap error at compose time. Declare a whitelist in the
authoring element:

```yaml
public:
  bst:
    overlap-whitelist:
    - /etc/some/file    # literal path, not a %{variable}
```

**A whitelist is not precedence.** It only silences the error — the file that
survives is decided by **staging order**, and your element can lose to a junction
element. To make the winner deterministic, add a runtime `depends:` on the component
that ships the original so yours stages after it, or do the overwrite in a later
phase. Then assert the result on the composed image, because a silent flip is
otherwise invisible. This shipped as a real regression in dakota (zram config
whitelisted but overwritten by the junction, dakota#1131).

## Remote-sandbox constraints

Builds run on BuildBarn workers, not on your machine. Two patterns that work
locally and fail remotely:

- **Never use `/dev/stdin` redirection.** `install -Dm644 /dev/stdin ... <<'EOF'`
  fails in sandboxes that do not mount `/proc`. Write inline files in two steps:
  `install -Dm644 /dev/null <target>` then `cat > <target> <<'EOF'`. Heredocs
  themselves are fine; only the `/dev/stdin` indirection breaks. This regressed in
  dakota across nine element sites after the lesson was first written (dakota#1298)
  — check for it in review.
- **Go builds need an explicit `GOROOT`.** The FSDK Go toolchain installs its
  standard library under `%{libdir}/go`, and dependent elements do not inherit
  `GOROOT_BOOTSTRAP`. Set `GOROOT: "%{libdir}/go"` in any element invoking
  `go build`, or remote actions fail with `go: cannot find GOROOT directory`.

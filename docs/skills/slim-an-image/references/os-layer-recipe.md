# Slim an Image — The OS-Layer SLIM Recipe

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

## Why a manual recipe

FSDK split-rule domains only cover:
`devel, debug, doc, sysconf, tests, shells, static-blocklist, license, locale,
vm-only, zoneinfo`. The largest **runtime-domain** bloat has *no domain* to exclude
it, so it must be removed explicitly with `rm` (in FSDK 25.08, this includes bash,
which lives in the `runtime` split domain; in FSDK 26.08+, `runtime-minimal` drops bash
and coreutils, moving them to `runtime-gnu`).
The shared commands live in `include/slim.yml` as BuildStream variables. Each
OCI element includes that fragment with `variables: (@): include/slim.yml` and
references either `%{slim-distroless-commands}` or
`%{slim-shell-enabled-commands}`. This keeps the lab-runner shell exception
explicit while preventing recipe drift.

### A split domain does not necessarily contain what its name implies

This is the single most expensive assumption in this repo, and there are now **two confirmed
instances** — enough to treat as a rule rather than a quirk:

| You exclude | You expect gone | Actually still shipped |
| --- | --- | --- |
| `shells` | bash | bash — it lives in the `runtime` domain (documented in AGENTS.md) |
| `debug` | debug symbols | **~905 KB of separated DWARF, was in every image — now stripped (see below)** |

The `shells`→bash leak is still live. The `debug` leak **was** live: both
`elements/base/base-runtime.bst` and `elements/static/static-runtime.bst` list
`debug` under `compose exclude:`, and these survived it:

```
487551  usr/lib/debug/dwz/bootstrap/glibc.bst/x86_64-unknown-linux-gnu
417560  usr/lib/debug/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2.debug
```

Every base-derived image carried it (~2.3% of a ~45 MB rootfs; `static` is not
carved from `base`). Nothing at runtime reads separated DWARF, so it is a safe
unconditional `rm`. It is now removed by `include/slim.yml` (`rm -rf "$L"/usr/lib/debug`
in both the distroless and shell-enabled recipes) and enforced by the
`no-debug-symbols` `just verify` gate on every distroless image — the ready-to-enable
gate in `scripts/verify_contract.py`'s `FORBIDDEN` is flipped on, so a regression
fails the merge contract rather than shipping silently. The recipe change and the
gate landed together: the gate is only honest now that the recipe satisfies it.

**The rule: never trust `compose exclude:` on its own — verify against the built rootfs.**

```console
$ podman export "$(podman create IMAGE)" | tar -tvf - | grep <what-you-excluded>
```

If a domain turns out to leak, the fix belongs in `include/slim.yml` as an explicit `rm`
alongside the other runtime-domain removals — **not** in the compose excludes, which have
already been shown not to hold. Pair it with a `just verify` gate: the existing "sanitizer/
fortran bloat must NOT be present" and "locale/build-tool bloat must NOT be present" gates
exist for exactly this reason, and a silent regression here is otherwise invisible.

## Applies to every image — not just glibc images

Even an image *intended* to be static (no glibc by design, e.g. one that only adds
tzdata + CA certs) **must run the full SLIM recipe**. Reason: `tzdata.bst` has a runtime dep on
`runtime-minimal`, which carries glibc, gcc runtimes (libasan, libtsan, libgfortran),
and terminfo into any compose that includes it. Skipping the SLIM recipe on a
"minimal" image will fail the slim gate of `just verify`.

This is not hypothetical: the repo's own `static` tier intended exactly that and **ships full
glibc anyway** — 88 shared objects, 15.9 MB compressed, differing from `base` by two files
(#116). Declaring a tier "static" in a description does not make it so. If you intend a
libc-free rootfs, you must compose the *produced files* (the cert bundle, zoneinfo) rather than
depend on the components, because `ca-certificates` pulls p11-kit and therefore glibc — and you
must verify the result with `tar -t`, not trust the element's own description.

## Risk tiers

**Zero risk — always cut:**
- gcc sanitizer runtimes `lib{asan,tsan,lsan,ubsan,hwasan}.so*` (~5 MB) — debug only.
- `libgfortran.so*` (~3.6 MB) — FORTRAN runtime pulled by gcc-libs.
- glibc `locale-archive`, `usr/share/i18n/charmaps` (~3 MB).
- leaked build tools: `localedef`, `sln`, `iconvconfig`, `ldconfig`, `pcre2test`.
- extra pcre2 widths `libpcre2-16/32`, `libpcre2-posix` (keep the 8-bit lib).

**Medium risk — trim, don't gut:**
- `gconv/` charset modules (~8 MB). Keep `gconv-modules*`, `UTF*`, `UNICODE*`,
  `ISO8859-1`, `ISO8859-15`, `CP1252`, `ANSI_X3.110`. Dropping a charset makes
  `iconv`/`.decode()` raise `LookupError` for that encoding (UTF-8 is built into
  glibc and always works).

**Do NOT cut (crash-preventers, cheap):**
- `tzdata` (`usr/share/zoneinfo`, ~2.6 MB) — python `zoneinfo` raises
  `ZoneInfoNotFoundError` without it. This is our differentiator vs suites that
  make you `pip install tzdata`.
- CA certificates + `usr/share/pki` trust source.
- `libstdc++`, `libgcc_s`, `libgomp` — C++ / OpenMP runtimes apps link.
- `usr/share/terminfo` (~12 MB unpacked, ~0.5 MB compressed) — kept since #101:
  without it a container must lie about the host TERM or vendor entries, both
  of which caused real color/rendering bugs downstream. `x/xterm-ghostty` is
  compiled in on top by `base/terminfo-ghostty.bst` (#105) — see
  [`verify-distroless/SKILL.md`](../../verify-distroless/SKILL.md).

## Sandbox constraint

The oci-builder sandbox has **no `find`**. Use shell globs + `case`:

```sh
for g in "$L"/usr/lib/*/gconv; do
  [ -d "$g" ] || continue
  for f in "$g"/*; do
    case "${f##*/}" in
      gconv-modules*|UTF*|UNICODE*|ISO8859-1.so|ISO8859-15.so|CP1252.so|ANSI_X3.110.so) : ;;
      *) rm -f "$f" ;;
    esac
  done
done
```

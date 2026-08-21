#!/usr/bin/env python3
"""Derive an image's verification contract from its catalog record.

The Justfile shells out to this so that adding an image never means editing a
case statement. Emits shell-quoted values for `eval`.

Usage:
    python3 scripts/verify_contract.py <image> --env
"""
from __future__ import annotations

import argparse
import shlex

import catalog

# Paths that must never appear in a distroless rootfs listing. These encode the
# five gates just verify has always applied, plus the leak checks the factory
# design calls for.
FORBIDDEN = {
    "no-shell": r"(^|/)(ba)?sh$",
    "no-sanitizers": r"/lib(asan|tsan|lsan|ubsan|hwasan|gfortran)\.so",
    "no-locale-archive": (
        r"usr/lib(/[^/]*)?/locale/locale-archive$|usr/share/i18n/charmaps/"
        r"|/(localedef|sln|iconvconfig|ldconfig|pcre2test|pcre2grep)$"
        r"|libpcre2-(16|32|posix)\.so"
    ),
    # NOT YET ENABLED -- these fail against today's images and belong to the
    # Phase 3 pruning plan, which is what makes them satisfiable:
    #   "no-debug-symbols": r"^usr/lib/debug/",
    #   "no-element-names": r"\.bst($|/)",
    #
    # base genuinely ships usr/lib/debug/dwz/bootstrap/glibc.bst/... because
    # the FSDK debug split hasn't been applied yet. Enabling these gates before
    # Phase 3 would break the merge contract.
}

# Required of every DISTROLESS image regardless of record contents, because
# these are the repo's documented distroless contract ("slim by default; keep
# tzdata + common charsets + CA certs"), not per-image choices.
#
# They must NOT be derived from gates.require_paths. The old hand-written
# recipe applied both to every non-lab-runner image; deriving them per record
# silently dropped the tzdata check for `static`, whose record declares no
# require_paths. A gate that stops checking is the exact failure this task is
# most at risk of, so the baseline is unconditional for the kind.
#
# They are NOT applied to shell-enabled images: the old recipe put both checks
# in its non-lab-runner branch, so adding them to lab-runner would be a new
# gate it never had.
BASELINE_PATHS_DISTROLESS = [
    "usr/share/zoneinfo/UTC",
]

# The old recipe accepted EITHER of these CA paths, not one fixed path:
#   grep -qE '^etc/(pki/tls/certs/ca-bundle\.crt|ssl/certs/ca-certificates\.crt)$'
# Narrowing to a single path asserts something the old gate never asserted.
# At least one of these must be present in every distroless image.
BASELINE_ANY_PATHS_DISTROLESS = [
    "etc/pki/tls/certs/ca-bundle.crt",
    "etc/ssl/certs/ca-certificates.crt",
]

# Gates that the old recipe applied ONLY in its non-lab-runner branch. A
# shell-enabled image never had them, so applying them would be a new gate --
# a behaviour change, which this plan forbids.
DISTROLESS_ONLY_GATES = ("no-sanitizers", "no-locale-archive")


def gates_for(record: dict) -> dict:
    """The full verification contract for one image."""
    forbid = dict(FORBIDDEN)
    if record["kind"] == "shell-enabled":
        del forbid["no-shell"]
        for gate in DISTROLESS_ONLY_GATES:
            forbid.pop(gate, None)

    require_binaries = list(record.get("gates", {}).get("require_binaries", []))
    if record["kind"] == "shell-enabled" and "bash" not in require_binaries:
        require_binaries.insert(0, "bash")

    return {
        "name": record["name"],
        "kind": record["kind"],
        "max_bytes": record["size_ceiling_mib"] * 1024 * 1024,
        "forbid": forbid,
        "require_paths": list(record.get("gates", {}).get("require_paths", [])),
        "require_binaries": require_binaries,
    }


def require_paths_for(record: dict) -> list[str]:
    """Combined required-paths list for one image: record paths + kind baseline.

    dict.fromkeys preserves order and de-duplicates: several records already
    list usr/share/zoneinfo/UTC explicitly.
    """
    record_paths = list(record.get("gates", {}).get("require_paths", []))
    baseline = BASELINE_PATHS_DISTROLESS if record["kind"] == "distroless" else []
    return list(dict.fromkeys(record_paths + baseline))


def require_any_paths_for(record: dict) -> list[str]:
    """Paths of which at least one must be present.

    For distroless images this is the CA-cert alternatives; for shell-enabled
    images the old recipe checked neither, so the list is empty.
    """
    if record["kind"] == "distroless":
        return list(BASELINE_ANY_PATHS_DISTROLESS)
    return []


def smoke_argv(record: dict) -> list[str]:
    """Arguments to append to `podman run --rm <ref>` for the smoke test.

    Returns [] for an image with no smoke block (base, static); the Justfile
    skips the smoke step entirely in that case, matching today's behaviour.
    """
    smoke = record.get("smoke")
    if not smoke:
        return []
    argv: list[str] = []
    override = smoke.get("entrypoint_override")
    if override:
        argv += ["--entrypoint", override[0]]
        argv += override[1:]
    argv += smoke["args"]
    return argv


def smoke_split(record: dict) -> tuple[list[str], list[str]]:
    """Split smoke_argv into podman OPTIONS (before REF) and CMD ARGS (after).

    "--entrypoint X" must precede the image reference; CMD args follow it.
    smoke_argv() returns them interleaved; we split at the end of --entrypoint.
    """
    full = smoke_argv(record)
    opts: list[str] = []
    cmd_args: list[str] = []
    i = 0
    while i < len(full):
        if full[i] == "--entrypoint" and i + 1 < len(full):
            opts += ["--entrypoint", full[i + 1]]
            i += 2
        elif full[i].startswith("--entrypoint="):
            opts.append(full[i])
            i += 1
        else:
            cmd_args = full[i:]
            break
    return opts, cmd_args


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image")
    parser.add_argument("--env", action="store_true", required=True)
    args = parser.parse_args()

    record = catalog.load_record(catalog.CATALOG_DIR / f"{args.image}.yaml")
    gates = gates_for(record)

    print(f"IMG_KIND={shlex.quote(gates['kind'])}")
    print(f"MAX_BYTES={gates['max_bytes']}")
    print(f"FORBID_PATTERNS={shlex.quote(chr(10).join(gates['forbid'].values()))}")
    print(f"FORBID_NAMES={shlex.quote(chr(10).join(gates['forbid'].keys()))}")
    print("REQUIRE_PATHS=" + shlex.quote(chr(10).join(require_paths_for(record))))
    print("REQUIRE_ANY_PATHS=" + shlex.quote(chr(10).join(require_any_paths_for(record))))
    print(f"REQUIRE_BINARIES={shlex.quote(chr(10).join(gates['require_binaries']))}")
    opts, cmd_args = smoke_split(record)
    # One argument per line, exactly like FORBID_PATTERNS/REQUIRE_PATHS above:
    # the Justfile mapfiles these into bash arrays, so an argument containing
    # a space or a glob character survives podman run as exactly one argument.
    print(f"SMOKE_OPTS={shlex.quote(chr(10).join(opts))}")
    print(f"SMOKE_ARGS={shlex.quote(chr(10).join(cmd_args))}")
    # shell_probe is a bash one-liner declared in shell-enabled records; empty
    # string for distroless images, which have no shell to run probes in.
    shell_probe = record.get("smoke", {}).get("shell_probe", "") or ""
    print(f"SHELL_PROBE={shlex.quote(shell_probe)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

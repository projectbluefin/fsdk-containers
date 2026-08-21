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

# Always required of a distroless image, regardless of record contents.
BASELINE_PATHS = [
    "etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",
]


def gates_for(record: dict) -> dict:
    """The full verification contract for one image."""
    forbid = dict(FORBIDDEN)
    if record["kind"] == "shell-enabled":
        del forbid["no-shell"]

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
    print(
        "REQUIRE_PATHS="
        + shlex.quote(chr(10).join(gates["require_paths"] + BASELINE_PATHS))
    )
    print(f"REQUIRE_BINARIES={shlex.quote(chr(10).join(gates['require_binaries']))}")
    # Split smoke_argv into podman OPTIONS (before REF) and CMD ARGS (after).
    # "--entrypoint X" must precede the image reference; CMD args follow it.
    # smoke_argv() returns them interleaved; we split at the end of --entrypoint.
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
    print(f"SMOKE_OPTS={shlex.quote(' '.join(opts))}")
    print(f"SMOKE_ARGS={shlex.quote(' '.join(cmd_args))}")
    # shell_probe is a bash one-liner declared in shell-enabled records; empty
    # string for distroless images, which have no shell to run probes in.
    shell_probe = record.get("smoke", {}).get("shell_probe", "") or ""
    print(f"SHELL_PROBE={shlex.quote(shell_probe)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

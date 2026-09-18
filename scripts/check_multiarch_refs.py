#!/usr/bin/env python3
"""Verify that multi-arch element source refs are updated symmetrically.

When an element has architecture-conditional sources (e.g., x86_64 and aarch64),
a version bump or source ref update must update the refs for all architectures,
not leave one stale.

Usage:
    # Check working tree against BASE_SHA (e.g. in PR CI or refresh workflow):
    python3 scripts/check_multiarch_refs.py --base <base-sha>

    # Check commits between BASE and HEAD:
    python3 scripts/check_multiarch_refs.py --base <base-sha> --head HEAD

    # Check specific files against a base revision:
    python3 scripts/check_multiarch_refs.py --base <base-sha> elements/lab-runner/kubectl.bst
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys

import yaml

# Matches the arch name out of a BuildStream (?) condition key, e.g.
# `arch == "x86_64"` or `arch == 'riscv64'`. Any quoted identifier is
# accepted -- the set of arches BuildStream supports is not this script's
# business to enumerate.
_ARCH_CONDITION = re.compile(r'arch\s*==\s*["\']([\w-]+)["\']')


def extract_arch_refs(content: str) -> dict[str, str]:
    """Extract architecture-specific source refs from a .bst file's YAML.

    Walks each entry under `sources:` for a BuildStream `(?)` conditional
    block keyed on `arch ==`, and returns the `ref:` each arch resolves to
    -- whatever form it takes (a bare digest, or a `git_repo` describe-form
    string like `v1.0.0-0-gabc123...`). Returns a dict mapping arch name to
    its ref string.
    """
    try:
        doc = yaml.safe_load(content)
    except yaml.YAMLError:
        return {}
    if not isinstance(doc, dict):
        return {}

    arch_refs: dict[str, str] = {}
    for source in doc.get("sources") or []:
        if not isinstance(source, dict):
            continue
        conditional = source.get("(?)")
        if not isinstance(conditional, list):
            continue
        for entry in conditional:
            if not isinstance(entry, dict):
                continue
            for condition, body in entry.items():
                arch_match = _ARCH_CONDITION.search(str(condition))
                if not arch_match or not isinstance(body, dict):
                    continue
                ref = body.get("ref")
                if ref is not None:
                    arch_refs[arch_match.group(1)] = str(ref)

    return arch_refs


def check_parity(
    file_path: str,
    base_content: str,
    head_content: str,
) -> str | None:
    """Check whether multi-arch refs in file_path were updated symmetrically.

    Returns an error message string if asymmetric, or None if symmetric / not applicable.
    """
    base_refs = extract_arch_refs(base_content)
    head_refs = extract_arch_refs(head_content)

    # Enforce parity across every arch the element conditions a ref on, not
    # just x86_64/aarch64 -- an element with a ppc64le or riscv64 ref is just
    # as vulnerable to one arch getting left behind.
    if len(base_refs) < 2:
        return None

    changed = {arch: base_refs[arch] != head_refs.get(arch) for arch in base_refs}
    if len(set(changed.values())) > 1:
        detail = ", ".join(f"{arch} changed={v}" for arch, v in sorted(changed.items()))
        return (
            f"{file_path}: asymmetric multi-arch ref update ({detail}). "
            f"All architecture refs must be updated together."
        )

    return None


def get_git_file_content(rev: str, file_path: str) -> str | None:
    """Retrieve file content from git at a given revision."""
    try:
        return subprocess.check_output(
            ["git", "show", f"{rev}:{file_path}"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return None


def get_changed_files(base_rev: str, head_rev: str | None) -> list[str]:
    """List .bst files changed between base_rev and head_rev (or working tree)."""
    cmd = ["git", "diff", "--name-only", "--diff-filter=ACMR"]
    if head_rev:
        cmd.append(f"{base_rev}...{head_rev}")
    else:
        cmd.append(base_rev)
    cmd.extend(["--", "elements/*.bst", "elements/**/*.bst"])

    try:
        output = subprocess.check_output(cmd, text=True)
        return [line.strip() for line in output.splitlines() if line.strip()]
    except subprocess.CalledProcessError:
        cmd_direct = ["git", "diff", "--name-only", "--diff-filter=ACMR", base_rev]
        if head_rev:
            cmd_direct.append(head_rev)
        cmd_direct.extend(["--", "elements/*.bst", "elements/**/*.bst"])
        output = subprocess.check_output(cmd_direct, text=True)
        return [line.strip() for line in output.splitlines() if line.strip()]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--base",
        default="HEAD",
        help="Base git commit/ref to compare against (default: HEAD)",
    )
    parser.add_argument(
        "--head",
        default=None,
        help="Head git commit/ref (if omitted, compares working tree against base)",
    )
    parser.add_argument(
        "files",
        nargs="*",
        help="Optional specific .bst files to check",
    )

    args = parser.parse_args(argv)

    files_to_check = args.files
    if not files_to_check:
        files_to_check = get_changed_files(args.base, args.head)

    errors: list[str] = []
    checked_count = 0

    for file_path in files_to_check:
        if not file_path.endswith(".bst"):
            continue

        base_content = get_git_file_content(args.base, file_path)
        if base_content is None:
            # File was added in this revision; nothing to diff against
            continue

        if args.head:
            head_content = get_git_file_content(args.head, file_path)
        else:
            disk_path = Path(file_path)
            if not disk_path.exists():
                # File was deleted in working tree
                continue
            head_content = disk_path.read_text(encoding="utf-8")

        if head_content is None:
            continue

        err = check_parity(file_path, base_content, head_content)
        checked_count += 1
        if err:
            errors.append(err)

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    print(f"OK: multi-arch ref parity check passed ({checked_count} element(s) checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

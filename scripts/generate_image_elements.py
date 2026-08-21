#!/usr/bin/env python3
"""Generate BuildStream elements from catalog/<name>.yaml records.

Usage:
    python3 scripts/generate_image_elements.py --write   # regenerate elements
    python3 scripts/generate_image_elements.py --check   # fail if stale (CI gate)

Every file this writes carries a DO-NOT-EDIT header naming its record. Editing
a generated element by hand is always wrong: the change is silently reverted on
the next --write, and the --check gate fails the pull request in the meantime.
Change the record instead.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

import catalog

REPO_ROOT = catalog.REPO_ROOT
ELEMENTS = REPO_ROOT / "elements"


def _header(name: str, what: str) -> str:
    return (
        f"# DO NOT EDIT. Generated from catalog/{name}.yaml by\n"
        f"# scripts/generate_image_elements.py ({what}).\n"
        f"# Change the record, then run: just catalog-write\n"
    )


def render_compose(record: dict) -> str:
    """The compose element that chisels a stack down to runtime-only."""
    name = record["name"]
    lines = [_header(name, "compose")]
    lines.append("kind: compose")
    lines.append(
        f"description: Chisel the {name} stack down to runtime-only, distroless."
        if record["kind"] == "distroless"
        else f"description: Chisel the {name} stack down to its runtime contract."
    )
    lines.append("")
    lines.append("build-depends:")
    lines.append(f"  - {name}/{name}-stack.bst")
    lines.append("")
    lines.append("config:")
    lines.append("  exclude:")

    omissions = {
        e["domain"]: e["reason"]
        for e in record.get("compose", {}).get("exclude_omit", [])
    }
    for domain in catalog.compose_exclude(record):
        lines.append(f"    - {domain}")
    for domain, reason in sorted(omissions.items()):
        wrapped = " ".join(reason.split())
        lines.append(f"    # NOT excluded -- {domain}: {wrapped}")
    return "\n".join(lines) + "\n"


def render_stack(record: dict) -> str:
    """The stack element listing everything this image depends on."""
    name = record["name"]
    lines = [_header(name, "stack")]
    lines.append("kind: stack")
    desc_line = yaml.dump({"description": record["description"]}, default_flow_style=False).rstrip()
    lines.append(desc_line)

    if record.get("notes"):
        lines.append("")
        for line in record["notes"].rstrip().splitlines():
            lines.append(f"# {line}".rstrip())

    lines.append("")
    lines.append("depends:")
    if record["stack"].get("base"):
        lines.append(f"  - {record['stack']['base']}")
    for component in record["stack"]["components"]:
        lines.append(f"  - {component}")
    for extra in record["stack"].get("extra_depends", []):
        lines.append(f"  - {extra}")
    return "\n".join(lines) + "\n"


RENDERERS = {
    "stack": (render_stack, lambda n: ELEMENTS / n / f"{n}-stack.bst"),
    "compose": (render_compose, lambda n: ELEMENTS / n / f"{n}-runtime.bst"),
}


def _targets() -> list[tuple[Path, str]]:
    out = []
    for record in catalog.load_all():
        for renderer, path_for in RENDERERS.values():
            out.append((path_for(record["name"]), renderer(record)))
    return out


def write() -> list[Path]:
    written = []
    for path, text in _targets():
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or path.read_text() != text:
            path.write_text(text)
            written.append(path)
    return written


def check() -> list[Path]:
    """Paths whose committed content differs from what the record generates."""
    return [
        path
        for path, text in _targets()
        if not path.exists() or path.read_text() != text
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true", help="regenerate elements")
    group.add_argument("--check", action="store_true", help="fail if stale")
    args = parser.parse_args()

    if args.write:
        for path in write():
            print(f"wrote {path.relative_to(REPO_ROOT)}")
        return 0

    stale = check()
    for path in stale:
        print(
            f"STALE: {path.relative_to(REPO_ROOT)} does not match its catalog "
            f"record. Run: just catalog-write",
            file=sys.stderr,
        )
    return 1 if stale else 0


if __name__ == "__main__":
    raise SystemExit(main())

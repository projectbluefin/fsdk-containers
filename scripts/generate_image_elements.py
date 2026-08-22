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


def yaml_single_quote(s: object) -> str:
    """Render s as a YAML single-quoted scalar.

    The only escape in a single-quoted YAML scalar is '' for an apostrophe.
    Interpolating a raw value into a '...' context lets an apostrophe in a
    description, entrypoint, or keyword silently corrupt the nested YAML of
    the build-oci heredoc.
    """
    return "'" + str(s).replace("'", "''") + "'"


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
    # Emitted in the record's order, verbatim. Do not sort, group or dedupe --
    # order affects the BuildStream cache key.
    for dep in record["stack"]["depends"]:
        lines.append(f"  - {dep}")
    return "\n".join(lines) + "\n"


SHARED_LABELS = [
    ("org.opencontainers.image.vendor", "Project Bluefin"),
    ("org.opencontainers.image.licenses", "Apache-2.0"),
    (
        "org.opencontainers.image.url",
        "https://github.com/projectbluefin/fsdk-containers",
    ),
    (
        "org.opencontainers.image.source",
        "https://github.com/projectbluefin/fsdk-containers",
    ),
    (
        "io.artifacthub.package.readme-url",
        "https://raw.githubusercontent.com/projectbluefin/fsdk-containers/main/README.md",
    ),
    ("io.artifacthub.package.logo-url", "https://projectbluefin.io/logo.png"),
    ("io.artifacthub.package.license", "Apache-2.0"),
    (
        "io.artifacthub.package.maintainers",
        '[{"name":"Project Bluefin","email":"maintainers@projectbluefin.io"}]',
    ),
]
# NOT in SHARED_LABELS: io.artifacthub.package.keywords nor
# io.artifacthub.package.category. keywords has 7 distinct values; both are
# emitted last (after maintainers) to preserve the committed label order, which
# affects the build-oci heredoc text and therefore the BST cache key.


def render_oci(record: dict) -> str:
    """The script element that slims the layer and builds the OCI image."""
    name = record["name"]
    slim_var = (
        "%{slim-shell-enabled-commands}"
        if record["kind"] == "shell-enabled"
        else "%{slim-distroless-commands}"
    )
    # static has its own init-script element; all others use the base one.
    # CATALOG DEVIATION: static.yaml declares init_script; this is the only
    # field added to static.yaml beyond what the brief specified, required to
    # reproduce the committed build-depends faithfully.
    init_script = record.get("init_script", "base/base-init-script.bst")
    lines = [_header(name, "oci")]
    lines.append("kind: script")
    lines.append("")
    lines.append("build-depends:")
    # FSDK 26.08 removed the shell from runtime-minimal, so the script sandbox
    # no longer gets /bin/sh implicitly. The SLIM recipe is a shell script, so
    # its interpreter is declared explicitly.
    lines.append("  - freedesktop-sdk.bst:bootstrap/bash.bst")
    lines.append("  - freedesktop-sdk.bst:bootstrap/coreutils.bst")
    lines.append("  - freedesktop-sdk.bst:components/oci-builder.bst")
    lines.append(f"  - {init_script}")
    lines.append(f"  - filename: {name}/{name}-runtime.bst")
    lines.append("    config:")
    lines.append("      location: /layer")
    lines.append("")
    lines.append("variables:")
    lines.append("  (@):")
    lines.append("    - include/slim.yml")
    lines.append("    - include/fsdk-version.yml")
    lines.append("")
    lines.append("config:")
    lines.append("  commands:")
    lines.append(f'    - "{slim_var}"')

    extra = record.get("slim", {}).get("extra")
    if extra:
        lines.append("    - |")
        for line in extra.rstrip().splitlines():
            lines.append(f"      {line}".rstrip())

    lines.append("    - |")
    lines.append("      if [ -d /initial_scripts ]; then")
    lines.append("        for i in /initial_scripts/*; do")
    lines.append('          "${i}" /layer')
    lines.append("        done")
    lines.append("      fi")

    lines.append("    - |")
    lines.append('      cd "%{install-root}"')
    lines.append("      build-oci <<EOF")
    lines.append("      mode: oci")
    lines.append("      gzip: disabled")
    lines.append("      images:")
    lines.append("      - os: linux")
    lines.append('        architecture: "%{go-arch}"')
    lines.append("        layer: /layer")
    lines.append(f'        comment: "fsdk-containers {name} image"')
    lines.append("        config:")
    # Only images that declare an entrypoint get one. base and static have no
    # Entrypoint in their committed oci elements; inventing one here would
    # change a published image, which this plan forbids.
    if record.get("entrypoint"):
        # Emit as inline list to match the committed format exactly.
        # The Entrypoint value is inside a build-oci heredoc, so the literal
        # text must be byte-for-byte identical to avoid changing the BST cache key.
        ep = ", ".join(yaml_single_quote(p) for p in record["entrypoint"])
        lines.append(f"          Entrypoint: [{ep}]")
    lines.append("          Labels:")
    lines.append(f"            'org.opencontainers.image.title': '{name}'")
    lines.append(
        f"            'org.opencontainers.image.description': "
        f"{yaml_single_quote(record['description'])}"
    )
    for key, value in SHARED_LABELS:
        lines.append(f"            '{key}': '{value}'")
    keywords = record.get("keywords", "distroless,freedesktop-sdk,bluefin")
    lines.append(
        f"            'io.artifacthub.package.keywords': {yaml_single_quote(keywords)}"
    )
    lines.append("            'io.artifacthub.package.category': 'integration-delivery'")
    lines.append("        index-annotations:")
    lines.append(
        f"          'org.opencontainers.image.ref.name': "
        f"'ghcr.io/projectbluefin/{name}:%{{fsdk-version}}'"
    )
    lines.append("      EOF")
    return "\n".join(lines) + "\n"


RENDERERS = {
    "stack": (render_stack, lambda n: ELEMENTS / n / f"{n}-stack.bst"),
    "compose": (render_compose, lambda n: ELEMENTS / n / f"{n}-runtime.bst"),
    "oci": (render_oci, lambda n: ELEMENTS / "oci" / f"{n}.bst"),
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

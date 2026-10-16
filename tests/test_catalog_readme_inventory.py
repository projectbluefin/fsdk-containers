"""The README image table is an inventory, so prove the inventory is complete.

``elements/targets.json`` calls itself "the SINGLE source of truth for the
GitHub Actions build/manifest matrices, ``just validate``, ``just sbom``/``sboms``,
and the pull-request build gate". Adding an image is deliberately designed to
require exactly one entry in ``oci_images``, its record at ``catalog/<name>.yaml``,
and its path ownership in ``image_paths``.

``README.md`` publishes a second list of the same set -- the ``## Images`` table --
and nothing compared the two. It drifted: ``review-runtime`` was registered in
``oci_images``, and so in the build matrix and every gate driven by it, while the
only consumer-facing list of what this repository ships had no row for it at all.
(That image is still not published: its build is blocked on ``node/node.bst``,
issue #289. Membership in ``oci_images`` is what this gate tracks, not the
registry.)

That is the same fail-open shape ``tests/test_catalog_ci_inventory.py`` closed
for the workflow inventory and ``tests/test_catalog_gate_coverage.py`` closed for
test modules: a hand-maintained copy that nobody checks.

These tests are a two-way ratchet over the table:

* every name in ``oci_images`` must have a ``ghcr.io/projectbluefin/<name>`` row
  in the README's OCI image section, and
* every image row in that section must name a real ``oci_images`` entry, so a
  deleted or renamed target cannot leave a row advertising an image that is no
  longer published.

They assert nothing about a row's size column or description; that text is a
human's job. Only the existence of a row is mechanical, so only that is gated.

The ``### Machine images (not distroless)`` table is deliberately excluded: the
``brew`` nspawn rootfs is not an OCI image and is not a member of ``oci_images``,
so it is not this inventory's business.
"""

from pathlib import Path
import json
import re
import unittest


ROOT = Path(__file__).parents[1]
TARGETS = ROOT / "elements" / "targets.json"
README = ROOT / "README.md"

# Heading that opens the OCI image table, and the heading that ends it. The
# machine-image table below the latter documents a non-OCI artifact.
OCI_SECTION_START = re.compile(r"^##\s+Images\s*$", re.MULTILINE)
OCI_SECTION_END = re.compile(r"^###\s+Machine images", re.MULTILINE)

# An image named in a table row's first cell, as the README writes it:
# | `ghcr.io/projectbluefin/base` | ~40 MB | ... |
ROW_IMAGE_RE = re.compile(r"^\|\s*`ghcr\.io/projectbluefin/([A-Za-z0-9._-]+)`\s*\|")


def _published_images():
    return sorted(json.loads(TARGETS.read_text())["oci_images"])


def _oci_section():
    text = README.read_text()
    start = OCI_SECTION_START.search(text)
    if start is None:
        return None
    rest = text[start.end() :]
    end = OCI_SECTION_END.search(rest)
    return rest if end is None else rest[: end.start()]


def _documented_images(section):
    return {
        m.group(1)
        for m in (ROW_IMAGE_RE.match(line) for line in section.splitlines())
        if m is not None
    }


class ReadmeImageInventoryTests(unittest.TestCase):
    def setUp(self):
        self.section = _oci_section()
        self.assertIsNotNone(
            self.section,
            "README.md no longer has an `## Images` heading; this gate reads the "
            "table under it. Restore the heading or update OCI_SECTION_START.",
        )
        self.published = _published_images()

    def test_every_published_image_has_a_readme_row(self):
        documented = _documented_images(self.section)
        missing = sorted(set(self.published) - documented)
        self.assertFalse(
            missing,
            "These images are published from `elements/targets.json` `oci_images` "
            f"but have no row in README.md's `## Images` table: {missing}. "
            "The README is the only consumer-facing list of what this repository "
            "ships; add a row for each.",
        )

    def test_every_readme_row_names_a_published_image(self):
        documented = _documented_images(self.section)
        unknown = sorted(documented - set(self.published))
        self.assertFalse(
            unknown,
            "README.md's `## Images` table advertises these images, but they are "
            f"not in `elements/targets.json` `oci_images`: {unknown}. Nothing "
            "builds or publishes them; remove the row or restore the target.",
        )


if __name__ == "__main__":
    unittest.main()

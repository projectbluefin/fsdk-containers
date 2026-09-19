"""`slim.includes` names a file and a variable; prove both actually exist.

`catalog/schema.json` constrains a `slim.includes` entry to the shape
``^slim-[a-z0-9]+\\.yml$`` and stops there.
`scripts/generate_image_elements.py` then spends the entry twice, deriving
both halves from the same string:

    variables: (@)     ->  - include/<entry>
    config: commands   ->  - "%{<stem>-commands}"

So a record can name a fragment that is not on disk, or a fragment can
define a variable spelled differently from its own filename, and every
Python gate still passes: ``tests/test_catalog_conformance.py`` regenerates
the element from the same record it is comparing against, so it agrees with
itself. The first thing to object is ``bst build`` in the `pr-build-oci`
matrix -- the slowest and most expensive signal in the repository -- for a
typo.

These tests close that loop on both sides: every entry resolves to a
fragment that defines the variable the generator will reference, and every
family fragment in ``include/`` is claimed by at least one record, so one
cannot rot unreferenced.
"""

from pathlib import Path
import sys
import unittest

import yaml

ROOT = Path(__file__).parents[1]
INCLUDE_DIR = ROOT / "include"
sys.path.insert(0, str(ROOT / "scripts"))

import catalog  # noqa: E402

# include/slim.yml is the shared OS-layer recipe every image gets
# unconditionally from the generator; it is not a per-family fragment and is
# never named in a record's slim.includes.
SHARED_OS_RECIPE = "slim.yml"


def _fragments_claimed_by_records():
    """{fragment filename: [record names that include it]}."""
    claimed = {}
    for record in catalog.load_all():
        for fragment in record.get("slim", {}).get("includes", []):
            claimed.setdefault(fragment, []).append(record["name"])
    return claimed


def _variable_name(fragment):
    """The variable the generator references for this fragment filename."""
    return f"{fragment[: -len('.yml')]}-commands"


class SlimIncludesResolveTests(unittest.TestCase):
    def test_every_included_fragment_exists(self):
        for fragment, records in sorted(_fragments_claimed_by_records().items()):
            with self.subTest(fragment=fragment):
                self.assertTrue(
                    (INCLUDE_DIR / fragment).is_file(),
                    f"catalog/{records[0]}.yaml includes {fragment}, but "
                    f"include/{fragment} does not exist. The generated OCI "
                    f"element would carry `- include/{fragment}`, which only "
                    f"fails at `bst build` time.",
                )

    def test_every_included_fragment_defines_the_variable_the_generator_uses(self):
        for fragment, records in sorted(_fragments_claimed_by_records().items()):
            path = INCLUDE_DIR / fragment
            if not path.is_file():
                continue  # reported by test_every_included_fragment_exists
            with self.subTest(fragment=fragment):
                loaded = yaml.safe_load(path.read_text())
                self.assertIsInstance(
                    loaded,
                    dict,
                    f"include/{fragment} must be a YAML mapping of "
                    f"BuildStream variables",
                )
                variable = _variable_name(fragment)
                self.assertIn(
                    variable,
                    loaded,
                    f"include/{fragment} must define {variable!r}: the "
                    f"generator emits `%{{{variable}}}` in the commands of "
                    f"every record that includes it ({', '.join(records)}). "
                    f"The variable name is the filename stem, so the file and "
                    f"the key have to be renamed together.",
                )

    def test_every_family_fragment_is_claimed_by_a_record(self):
        claimed = _fragments_claimed_by_records()
        on_disk = sorted(
            path.name
            for path in INCLUDE_DIR.glob("slim-*.yml")
            if path.name != SHARED_OS_RECIPE
        )
        unreferenced = [name for name in on_disk if name not in claimed]
        self.assertEqual(
            unreferenced,
            [],
            "these per-family slim fragments are in include/ but no "
            "catalog record lists them in slim.includes, so nothing composes "
            "them into an image: "
            f"{unreferenced}. Wire each one into the record it was written "
            "for, or delete it.",
        )

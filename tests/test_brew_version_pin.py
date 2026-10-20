"""The Homebrew release pin has one source of truth: brew-prefix.bst's track."""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).parents[1]


def single(pattern, path):
    matches = re.findall(pattern, (ROOT / path).read_text(), re.MULTILINE)
    if len(matches) != 1:
        raise AssertionError(f"{path}: expected one match for {pattern!r}, got {matches}")
    return matches[0]


class BrewVersionPinTest(unittest.TestCase):
    def test_artifact_version_matches_source_track(self):
        track = single(r"^  track: (\S+)$", "elements/brew/brew-prefix.bst")
        artifact = single(r'^  brew-version: "([^"]+)"$', "elements/oci/brew-nspawn.bst")
        self.assertEqual(artifact, track)

    def test_justfile_reads_the_pin_instead_of_restating_it(self):
        justfile = (ROOT / "Justfile").read_text()
        self.assertNotRegex(justfile, r'(?m)^brew_version := "')
        self.assertRegex(
            justfile,
            r"(?m)^brew_version := `sed -n 's/\^  track: //p' elements/brew/brew-prefix\.bst`$",
        )


if __name__ == "__main__":
    unittest.main()

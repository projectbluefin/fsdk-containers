"""Keep brew's independent PR build sensitive to shared build inputs."""

from fnmatch import fnmatchcase
from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]


class BrewWorkflowPathsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # BaseLoader preserves the GitHub Actions `on` key (YAML 1.1 would
        # otherwise interpret it as boolean True).
        cls.workflow = yaml.load(
            (ROOT / '.github/workflows/brew-nspawn.yml').read_text(),
            Loader=yaml.BaseLoader,
        )
        cls.paths = cls.workflow['on']['pull_request']['paths']

    def selects(self, path):
        # This workflow uses only literal paths and trailing /** patterns;
        # do not pretend fnmatch implements GitHub's full glob language.
        return any(fnmatchcase(path, pattern) for pattern in self.paths)

    def test_build_inputs_trigger_verification(self):
        for path in (
            'elements/brew/brew-prefix.bst',
            'elements/brew/brew-deps.bst',
            'elements/brew/brew-runtime.bst',
            'elements/oci/brew-nspawn.bst',
            'elements/base/base-stack.bst',
            'elements/base/terminfo-ghostty.bst',
            'elements/base/files/xterm-ghostty.terminfo',
            'elements/freedesktop-sdk.bst',
            'elements/gnome-build-meta.bst',
            'elements/plugins/buildstream-plugins-community.bst',
            'include/aliases.yml',
            'patches/freedesktop-sdk/0001-example.patch',
            'patches/gnome-build-meta/0001-example.patch',
            'patches/printing/cups/0001-example.patch',
            'project.conf',
            'Justfile',
            '.github/workflows/brew-nspawn.yml',
        ):
            with self.subTest(path=path):
                self.assertTrue(self.selects(path), path)

    def test_unrelated_changes_skip_expensive_build(self):
        for path in (
            'README.md',
            'docs/skills/nspawn-machine-image.md',
            'elements/oci/nginx.bst',
            'elements/nginx/nginx-stack.bst',
            '.github/workflows/ghcr-cleanup.yml',
        ):
            with self.subTest(path=path):
                self.assertFalse(self.selects(path), path)

    def test_schedule_dispatch_and_verification_are_preserved(self):
        self.assertEqual(self.workflow['on']['schedule'], [{'cron': '30 4 * * 1'}])
        self.assertIn('workflow_dispatch', self.workflow['on'])
        steps = self.workflow['jobs']['verify-brew']['steps']
        self.assertIn('just verify-brew', [step.get('run') for step in steps])


if __name__ == '__main__':
    unittest.main()

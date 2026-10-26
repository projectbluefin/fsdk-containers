"""include/slim-printing.yml: the recipe, its forbidden-path list and its gate
must agree, and the gate must fail closed.

The fragment is consumed across the junction by the printer applications, so
no catalog record, generated element or `just verify` in this repository ever
runs it. Without this test the first thing to notice a glob that matches
nothing, a forbidden-path line without an rm, or a gate that cannot expand
its own variable would be a consumer's OCI build, an hour or two in.

The recipe is exercised the way BuildStream runs it: each variable is
expanded like `%{...}` substitution and handed to bash in POSIX mode as one
`-e -c` script, against a synthetic /layer that holds one concrete instance
of every forbidden glob plus a keep-list of files a printer appliance needs
(measured on the published ghostscript/hplip/gutenprint images, #341).
"""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).parents[1]
FRAGMENT = ROOT / "include" / "slim-printing.yml"

# One concrete path per kind of wildcard the forbidden list uses, so each
# glob materialises into a file the recipe must remove. Order matters.
_MATERIALISE = [
    (r"\*\*/", "lib/python3.14/site-packages/pkg/"),
    (r"usr/lib/\*/", "usr/lib/x86_64-linux-gnu/"),
    (r"python3\*", "python3.14"),
    (r"libicu\*", "libicuuc"),
    (r"libxml2mod\*", "libxml2mod.cpython-314-x86_64-linux-gnu"),
    (r"\.so\*", ".so.1.2.3"),
    (r"\*\.opt-1\.pyc", "mod.cpython-314.opt-1.pyc"),
    (r"\*\.opt-2\.pyc", "mod.cpython-314.opt-2.pyc"),
    (r"EBCDIC-\*", "EBCDIC-AT-DE.so"),
    (r"IBM\*", "IBM037.so"),
    (r"config-\*", "config-3.14-x86_64-linux-gnu"),
    (r"pydoc3\*", "pydoc3.14"),
    (r"\*", "X"),
]

# Files the recipe must leave alone: entrypoint + coreutils, python with its
# plain .pyc and lzma (pyppd archives), HPLIP's declared runtime (gpg, perl,
# pygobject/cairo/dbus/PIL and the libraries under them), glibc NSS modules,
# p11-kit trust and OpenSSL modules (dlopen'd, invisible to a NEEDED walk),
# the common gconv charsets, compiled locales, gutenprint's translations,
# tzdata, the CA bundle, terminfo, PPD archives and license texts.
KEEP = [
    "usr/libexec/printer-app/entrypoint-common.sh",
    "usr/bin/bash",
    "usr/bin/cat",
    "usr/bin/python3",
    "usr/bin/python3.14",
    "usr/bin/curl",
    "usr/bin/gpg",
    "usr/bin/perl",
    "usr/bin/xz",
    "usr/bin/gs",
    "usr/bin/pdftops",
    "usr/bin/ippfind",
    "usr/bin/ldd",
    "usr/bin/hp-probe",
    "usr/lib/cups/filter/foomatic-rip",
    "usr/lib/python3.14/lzma.py",
    "usr/lib/python3.14/lib-dynload/_lzma.cpython-314-x86_64-linux-gnu.so",
    "usr/lib/python3.14/json/__init__.py",
    "usr/lib/python3.14/json/__pycache__/__init__.cpython-314.pyc",
    "usr/lib/python3.14/encodings/utf_8.py",
    "usr/lib/python3.14/xml/parsers/expat.py",
    "usr/lib/python3.14/site-packages/distro/__init__.py",
    "usr/lib/python3.14/site-packages/gi/__init__.py",
    "usr/lib/python3.14/site-packages/cairo/__init__.py",
    "usr/lib/python3.14/site-packages/dbus/__init__.py",
    "usr/lib/python3.14/site-packages/PIL/__init__.py",
    "usr/lib/python3.14/site-packages/pycairo-1.29.1.dist-info/METADATA",
    "usr/lib/x86_64-linux-gnu/libc.so.6",
    "usr/lib/x86_64-linux-gnu/libmvec.so.1",
    "usr/lib/x86_64-linux-gnu/libnss_files.so.2",
    "usr/lib/x86_64-linux-gnu/libnss_dns.so.2",
    "usr/lib/x86_64-linux-gnu/libnss_resolve.so.2",
    "usr/lib/x86_64-linux-gnu/libgio-2.0.so.0",
    "usr/lib/x86_64-linux-gnu/libgobject-2.0.so.0",
    "usr/lib/x86_64-linux-gnu/libgirepository-2.0.so.0",
    "usr/lib/x86_64-linux-gnu/libcairo.so.2",
    "usr/lib/x86_64-linux-gnu/libcairo-gobject.so.2",
    "usr/lib/x86_64-linux-gnu/libpixman-1.so.0",
    "usr/lib/x86_64-linux-gnu/libgcrypt.so.20",
    "usr/lib/x86_64-linux-gnu/libsqlite3.so.0",
    "usr/lib/x86_64-linux-gnu/libgdbm.so.6",
    "usr/lib/x86_64-linux-gnu/libselinux.so.1",
    "usr/lib/x86_64-linux-gnu/libpcre2-8.so.0",
    "usr/lib/x86_64-linux-gnu/libX11.so.6",
    "usr/lib/x86_64-linux-gnu/libxcb.so.1",
    "usr/lib/x86_64-linux-gnu/libxcb-render.so.0",
    "usr/lib/x86_64-linux-gnu/libxcb-shm.so.0",
    "usr/lib/x86_64-linux-gnu/libharfbuzz.so.0",
    "usr/lib/x86_64-linux-gnu/libharfbuzz-gobject.so.0",
    "usr/lib/x86_64-linux-gnu/libwebp.so.7",
    "usr/lib/x86_64-linux-gnu/libhwy.so.1",
    "usr/lib/x86_64-linux-gnu/libjxl.so.0",
    "usr/lib/x86_64-linux-gnu/libpoppler.so.163",
    "usr/lib/x86_64-linux-gnu/libpoppler-glib.so.8",
    "usr/lib/x86_64-linux-gnu/libtiff.so.6",
    "usr/lib/x86_64-linux-gnu/libjpeg.so.8",
    "usr/lib/x86_64-linux-gnu/libgnutls.so.30",
    "usr/lib/x86_64-linux-gnu/libgomp.so.1",
    "usr/lib/x86_64-linux-gnu/libdw-0.195.so",
    "usr/lib/x86_64-linux-gnu/gconv/gconv-modules",
    "usr/lib/x86_64-linux-gnu/gconv/UTF-16.so",
    "usr/lib/x86_64-linux-gnu/gconv/ISO8859-1.so",
    "usr/lib/x86_64-linux-gnu/gconv/CP1252.so",
    "usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-trust.so",
    "usr/lib/x86_64-linux-gnu/ossl-modules/legacy.so",
    "usr/lib/x86_64-linux-gnu/engines-3/afalg.so",
    "usr/lib/x86_64-linux-gnu/girepository-1.0/GLib-2.0.typelib",
    "usr/lib/locale/C.utf8/LC_CTYPE",
    "usr/lib/locale/en_US.utf8/LC_CTYPE",
    "usr/share/locale/de/LC_MESSAGES/gutenprint.mo",
    "usr/share/zoneinfo/UTC",
    "usr/share/terminfo/x/xterm",
    "usr/share/ppd/foomatic-ppds",
    "usr/share/hplip/base/g.py",
    "usr/share/icu/78.3/LICENSE",
    "usr/share/licenses/icu/LICENSE",
    "usr/share/misc/magic.mgc",
    "etc/pki/tls/certs/ca-bundle.crt",
]


def load_variables():
    loaded = yaml.safe_load(FRAGMENT.read_text())

    def expand(text, depth=0):
        if depth > 8:
            raise RecursionError("variable reference cycle in slim-printing.yml")
        return re.sub(
            r"%\{([A-Za-z0-9_-]+)\}",
            lambda m: expand(loaded[m.group(1)], depth + 1),
            text,
        )

    return loaded, {key: expand(value) for key, value in loaded.items()}


def forbidden_globs(loaded):
    return [line for line in loaded["slim-printing-forbidden-paths"].splitlines() if line]


def materialise(pattern):
    path = pattern
    for regex, replacement in _MATERIALISE:
        path = re.sub(regex, replacement, path)
    assert "*" not in path, pattern
    return path


def run_in_layer(script, layer):
    """Run a fragment variable the way the script element does (`sh -e -c`,
    where the sandbox's sh is bash), with /layer redirected to the fixture."""
    script = script.replace("L=/layer", f"L={layer}", 1)
    return subprocess.run(
        ["bash", "--posix", "-e", "-c", script],
        capture_output=True,
        text=True,
        check=False,
    )


class SlimPrintingFixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.loaded, cls.variables = load_variables()
        cls.globs = forbidden_globs(cls.loaded)

    def setUp(self):
        self.layer = Path(tempfile.mkdtemp(prefix="slim-printing-"))
        self.addCleanup(shutil.rmtree, self.layer, ignore_errors=True)
        # Directory globs (usr/lib/debug, python3*/unittest, site-packages/
        # setuptools ...) get a populated tree first, so a `rm -f` where
        # `rm -rf` was meant is caught; their materialised instance then
        # resolves to that directory instead of a file.
        for rel in ("usr/lib/debug/.build-id/ab/cdef.debug",
                    "usr/lib/python3.14/site-packages/setuptools/command/build.py",
                    "usr/lib/python3.14/unittest/mock.py",
                    "usr/share/i18n/locales/en_US"):
            self._touch(rel)
        self.forbidden_files = [materialise(g) for g in self.globs]
        for rel in self.forbidden_files + KEEP:
            self._touch(rel)
        (self.layer / "etc/pki/tls/certs/ca-bundle.crt").unlink()
        # The real image ships the CA bundle as an absolute symlink that only
        # resolves inside the container; the gate must accept it.
        (self.layer / "etc/pki/tls/certs/ca-bundle.crt").symlink_to(
            "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
        )

    def _touch(self, rel):
        path = self.layer / rel
        if path.is_dir():
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"x")

    def _present(self, rel):
        path = self.layer / rel
        return path.exists() or path.is_symlink()


class ForbiddenListTests(SlimPrintingFixture):
    def test_every_forbidden_glob_matches_before_the_recipe_runs(self):
        """A glob that matches nothing guards nothing: the gate must report
        each materialised instance on an unslimmed layer."""
        result = run_in_layer(self.variables["slim-printing-gate-commands"], self.layer)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        reported = {
            line.split("forbidden path present: ", 1)[1].lstrip("/")
            for line in result.stderr.splitlines()
            if "forbidden path present: " in line
        }
        for pattern, rel in zip(self.globs, self.forbidden_files):
            with self.subTest(glob=pattern):
                self.assertIn(rel, reported, f"{pattern!r} matched nothing")

    def test_recipe_removes_every_forbidden_path_and_only_those(self):
        result = run_in_layer(self.variables["slim-printing-commands"], self.layer)
        self.assertEqual(result.returncode, 0, result.stderr)
        survivors = [rel for rel in self.forbidden_files if self._present(rel)]
        self.assertEqual(survivors, [], "forbidden paths the recipe left behind")
        removed_keep = [rel for rel in KEEP if not self._present(rel)]
        self.assertEqual(removed_keep, [], "the recipe deleted files an app needs")
        for tree in ("usr/lib/debug", "usr/lib/python3.14/site-packages/setuptools",
                     "usr/lib/python3.14/unittest", "usr/share/i18n/locales"):
            self.assertFalse((self.layer / tree).exists(), f"{tree} survived")

    def test_gate_passes_after_the_recipe(self):
        run_in_layer(self.variables["slim-printing-commands"], self.layer)
        result = run_in_layer(self.variables["slim-printing-gate-commands"], self.layer)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("slim-printing: gate passed", result.stdout)


class GateFailsClosedTests(SlimPrintingFixture):
    def test_a_forbidden_path_that_comes_back_fails_the_gate_by_name(self):
        """The FSDK-bump regression the gate exists for: the recipe ran, then
        something staged a removed file again."""
        run_in_layer(self.variables["slim-printing-commands"], self.layer)
        self._touch("usr/lib/x86_64-linux-gnu/libicudata.so.79.1")
        result = run_in_layer(self.variables["slim-printing-gate-commands"], self.layer)
        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "forbidden path present: /usr/lib/x86_64-linux-gnu/libicudata.so.79.1",
            result.stderr,
        )

    def test_a_missing_keep_path_fails_the_gate(self):
        run_in_layer(self.variables["slim-printing-commands"], self.layer)
        (self.layer / "usr/lib/python3.14/lzma.py").unlink()
        result = run_in_layer(self.variables["slim-printing-gate-commands"], self.layer)
        self.assertEqual(result.returncode, 1)
        self.assertIn("required path missing: usr/lib/python3*/lzma.py", result.stderr)

    def test_missing_shared_entrypoint_fails_even_without_python(self):
        run_in_layer(self.variables["slim-printing-commands"], self.layer)
        shutil.rmtree(self.layer / "usr/lib/python3.14")
        (self.layer / "usr/bin/python3").unlink()
        shared = "usr/libexec/printer-app/entrypoint-common.sh"
        (self.layer / shared).unlink()
        result = run_in_layer(self.variables["slim-printing-gate-commands"], self.layer)
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"required path missing: {shared}", result.stderr)

    def test_python_keep_checks_only_apply_when_python_is_staged(self):
        """gutenprint-printer-app stages no python3; the gate must not demand
        an interpreter it never had."""
        run_in_layer(self.variables["slim-printing-commands"], self.layer)
        shutil.rmtree(self.layer / "usr/lib/python3.14")
        for name in ("python3", "python3.14"):
            (self.layer / "usr/bin" / name).unlink()
        result = run_in_layer(self.variables["slim-printing-gate-commands"], self.layer)
        self.assertEqual(result.returncode, 0, result.stderr)


class FragmentShapeTests(unittest.TestCase):
    def test_variables_expand_without_dangling_references(self):
        loaded, variables = load_variables()
        for key in ("slim-printing-commands", "slim-printing-gate-commands",
                    "slim-printing-forbidden-paths"):
            self.assertIn(key, loaded)
        for key, text in variables.items():
            with self.subTest(variable=key):
                self.assertNotRegex(text, r"%\{", "unexpanded BuildStream variable")
        # The gate embeds the list verbatim; a heredoc line that is not a
        # single relative glob would be read as one and match nothing.
        for line in forbidden_globs(loaded):
            with self.subTest(glob=line):
                self.assertNotRegex(line, r"\s|^/")


if __name__ == "__main__":
    unittest.main()

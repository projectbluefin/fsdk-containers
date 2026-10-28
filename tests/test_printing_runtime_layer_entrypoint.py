"""Host-only contract tests: no container, root privileges or printer needed."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / "elements/printing/files/entrypoint-common.sh"


class EntrypointTests(unittest.TestCase):
    def run_shell(self, code, **env):
        return subprocess.run(
            ["bash", "-euo", "pipefail", "-c", 'source "$LIBRARY"; ' + code],
            env={"PATH": os.environ["PATH"], "LIBRARY": str(LIBRARY), **env},
            text=True, capture_output=True, timeout=10,
        )

    def validate(self, **env):
        return self.run_shell(
            'printer_app_validate "Example Printer" "${FLOOR:-1}"; '
            'printf "%s\\n" "${printer_app_args[@]}"', **env
        )

    def test_source_has_no_side_effects(self):
        result = self.run_shell('printf "%s" "$(umask)"')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, "")

    def test_port_bounds_and_decimal_normalisation(self):
        for value, expected in [("1", "1"), ("80", "80"), ("65535", "65535"),
                                ("09100", "9100"), ("000001", "1")]:
            with self.subTest(value=value):
                result = self.validate(PORT=value)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("server-port=" + expected, result.stdout)
        for value in ("", None):
            result = self.validate(**({"PORT": value} if value is not None else {}))
            self.assertEqual(result.returncode, 0)
            self.assertNotIn("server-port", result.stdout)
        self.assertEqual(self.validate(PORT="1023", FLOOR="1024").returncode, 64)
        self.assertEqual(self.validate(PORT="01024", FLOOR="1024").returncode, 0)
        for floor in ("0", "65536", "00001", "x"):
            self.assertEqual(self.validate(FLOOR=floor).returncode, 64)

    def test_union_of_consumer_validation_refusals(self):
        cases = []
        for value in ("invalid", "18030abc", " 18030", "-1", "+18030", "0x4696",
                      "18030\n80", "123456", "9999999999999999999999999", "0", "00000", "65536", "99999"):
            cases.append((64, "PORT must be", {"PORT": value}))
        for value in ("no-tls", "none", "web-remote", "no-web-interface,web-remote",
                      "no-web-interface,", ",no-web-interface", "no-web-interface no-tls",
                      "No-Web-Interface"):
            cases.append((64, "PRINTER_APP_SERVER_OPTIONS", {"PRINTER_APP_SERVER_OPTIONS": value}))
        for value in ("../shadow", "login other", "-login", ".login", "a=b"):
            cases.append((64, "PAM service name", {"PRINTER_APP_AUTH_SERVICE": value}))
        for value in ("bad;group", "1admins", "-wheel", "two groups"):
            cases.append((64, "group name", {"PRINTER_APP_ADMIN_GROUP": value}))
        for value in ("cups", "nonexistent-pam-service", "login"):
            cases.append((78, "without PAM", {"PRINTER_APP_AUTH_SERVICE": value}))
        for value in ("wheel", "root", "unknown_group"):
            cases.append((78, "requires PRINTER_APP_AUTH_SERVICE", {"PRINTER_APP_ADMIN_GROUP": value}))
        cases.append((64, "group name", {"PRINTER_APP_AUTH_SERVICE": "cups", "PRINTER_APP_ADMIN_GROUP": "bad;group"}))
        cases.append((64, "PRINTER_APP_INSTANCE", {"PRINTER_APP_INSTANCE": "---!!!"}))
        for status, diagnostic, env in cases:
            with self.subTest(env=env):
                result = self.validate(**env)
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertIn(diagnostic, result.stderr)
                self.assertEqual(result.stdout, "")

    def test_options_instance_and_repeat_calls(self):
        result = self.validate(PRINTER_APP_SERVER_OPTIONS="no-web-interface", PRINTER_APP_INSTANCE="  Office -- north_2!!")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("server-options=no-web-interface", result.stdout)
        self.assertIn("system-name='Example Printer (Office-north_2)'", result.stdout)
        self.assertNotIn("NOTICE", result.stderr)
        result = self.validate(PRINTER_APP_INSTANCE="a" * 40)
        self.assertIn("(" + "a" * 24 + ")", result.stdout)
        self.assertIn("NOTICE", result.stderr)
        result = self.run_shell('PORT=9100 printer_app_validate Example; '
                                'printer_app_validate Example; '
                                'test "${#printer_app_args[@]}" = 0')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_state_probe_modes_and_seed_preservation(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "state"
            state.mkdir(mode=0o777)
            for directory in ("cups/ssl", ".cups/ssl", "spool"):
                (state / directory).mkdir(parents=True, mode=0o777)
                (state / directory / "private").write_text("secret")
                (state / directory / "private").chmod(0o666)
            snmp, quirks = Path(tmp) / "snmp", Path(tmp) / "quirks"
            snmp.write_text("default snmp")
            quirks.write_text("default quirks")
            code = ('printer_app_prepare_state "$STATE" example "$STATE/driver/run"; '
                    'printer_app_seed_cups "$STATE" "$SNMP" "$QUIRKS"; '
                    'touch "$STATE/new"')
            env = dict(STATE=str(state), SNMP=str(snmp), QUIRKS=str(quirks))
            result = self.run_shell(code, **env)
            self.assertEqual(result.returncode, 0, result.stderr)
            for directory in ("", "cups", "cups/ssl", ".cups", ".cups/ssl", "spool", "driver/run"):
                self.assertEqual((state / directory).stat().st_mode & 0o777, 0o700)
            for file in ("new", "cups/ssl/private", ".cups/ssl/private", "spool/private"):
                self.assertEqual((state / file).stat().st_mode & 0o777, 0o600)
            self.assertFalse(list(state.rglob(".write-check.*")))
            self.assertEqual((state / "cups/snmp.conf").read_text(), "default snmp")
            (state / "cups/snmp.conf").write_text("custom")
            (state / "usb/org.cups.usb-quirks").write_text("custom")
            self.assertEqual(self.run_shell(code, **env).returncode, 0)
            self.assertEqual((state / "usb/org.cups.usb-quirks").read_text(), "custom")
            self.assertEqual((state / "cups/snmp.conf").read_text(), "custom")
            (state / "cups/snmp.conf").unlink()
            (state / "cups/snmp.conf").symlink_to("missing")
            self.assertEqual(self.run_shell(code, **env).returncode, 0)
            self.assertTrue((state / "cups/snmp.conf").is_symlink())

    def test_state_failures_use_73(self):
        with tempfile.TemporaryDirectory() as tmp:
            for failure in ("mkdir", "mktemp", "rm", "chmod"):
                result = self.run_shell(
                    failure + '() { return 1; }; printer_app_prepare_state "$STATE" example', STATE=tmp)
                self.assertEqual(result.returncode, 73, (failure, result.stderr))
                self.assertIn("UID:GID", result.stderr)
            # Existing files with an invalid type or dangling target fail closed.
            path = Path(tmp) / "example.state"
            path.mkdir()
            self.assertEqual(self.run_shell('printer_app_prepare_state "$STATE" example', STATE=tmp).returncode, 73)
            path.rmdir()
            path.symlink_to("missing")
            self.assertEqual(self.run_shell('printer_app_prepare_state "$STATE" example', STATE=tmp).returncode, 73)

    def test_state_symlinks_refused_before_any_change(self):
        for link in ("", "spool", "cups", "cups/ssl", "driver", "driver/run"):
            with self.subTest(link=link), tempfile.TemporaryDirectory() as tmp:
                outside = Path(tmp) / "outside"
                outside.mkdir(mode=0o755)
                outside.chmod(0o755)
                state = Path(tmp) / "state"
                target = state / link if link else state
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(outside)
                result = self.run_shell(
                    'printer_app_prepare_state "$STATE" example "$STATE/driver/run"', STATE=str(state))
                self.assertEqual(result.returncode, 73, result.stderr)
                self.assertIn("must not be a symlink", result.stderr)
                self.assertEqual(outside.stat().st_mode & 0o777, 0o755)
                self.assertEqual(list(outside.iterdir()), [])

    def test_state_root_secured_only_when_owned(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "state"
            state.mkdir()
            state.chmod(0o777)
            result = self.run_shell(
                'printer_app_owns() { [[ "$1" != "$STATE" ]]; }; '
                'printer_app_prepare_state "$STATE" example', STATE=str(state))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(state.stat().st_mode & 0o777, 0o777)
            self.assertEqual((state / "spool").stat().st_mode & 0o777, 0o700)

    def test_supervisor_exit_signal_and_readiness_cleanup(self):
        # Real processes and a real Unix socket; no system daemons are launched.
        stub = '''#!/usr/bin/env python3
import os, pathlib, socket, time
name = pathlib.Path(__file__).name
root = pathlib.Path(os.environ['RUN'])
(root / (name + '.started')).write_text(str(os.getpid()))
if name == 'dbus-daemon' and os.environ.get('NO_READY') != name:
    sock = socket.socket(socket.AF_UNIX)
    sock.bind(str(root / 'dbus/system_bus_socket'))
if name == 'avahi-daemon' and os.environ.get('NO_READY') != name:
    (root / 'avahi-daemon/pid').write_text(str(os.getpid()))
if os.environ.get('FAIL_SERVICE') == name:
    time.sleep(0.3)
    raise SystemExit(int(os.environ['EXIT_CODE']))
while True:
    time.sleep(0.1)
'''
        cases = [(name, status, None) for name in ("dbus-daemon", "avahi-daemon", "app") for status in (0, 7)]
        cases += [(None, 143, sig) for sig in (signal.SIGTERM, signal.SIGINT)]
        cases += [(name, 1, None) for name in ("no-dbus", "no-avahi")]
        for name, expected, sig in cases:
            with self.subTest(service=name, status=expected, signal=sig), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                (root / "bin").mkdir()
                for command in ("dbus-daemon", "avahi-daemon", "app"):
                    path = root / "bin" / command
                    path.write_text(stub)
                    path.chmod(0o755)
                env = {"PATH": str(root / "bin") + ":" + os.environ["PATH"], "LIBRARY": str(LIBRARY),
                       "RUN": tmp, "FAIL_SERVICE": name or "", "EXIT_CODE": str(expected)}
                if name in ("no-dbus", "no-avahi"):
                    env["NO_READY"] = "dbus-daemon" if name == "no-dbus" else "avahi-daemon"
                process = subprocess.Popen(
                    ["bash", "-euo", "pipefail", "-c", 'source "$LIBRARY"; printer_app_supervise "$RUN" app'],
                    env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True,
                )
                try:
                    if sig:
                        deadline = time.monotonic() + 5
                        while not (root / "app.started").exists() and time.monotonic() < deadline:
                            time.sleep(0.01)
                        self.assertTrue((root / "app.started").exists())
                        process.send_signal(sig)
                    _, stderr = process.communicate(timeout=8)
                    self.assertEqual(process.returncode, 1 if expected == 0 else expected, stderr)
                    for record in root.glob("*.started"):
                        with self.assertRaises(ProcessLookupError):
                            os.kill(int(record.read_text()), 0)
                finally:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.communicate()

    def test_runtime_wiring(self):
        import yaml
        element = yaml.safe_load((ROOT / "elements/printing/entrypoint-common.bst").read_text())
        self.assertEqual(element["sources"][0]["path"], str(LIBRARY.relative_to(ROOT)))
        self.assertIn("/usr/libexec/printer-app/entrypoint-common.sh", element["config"]["install-commands"][0])
        stack = yaml.safe_load((ROOT / "elements/printing/runtime-stack.bst").read_text())
        self.assertIn("printing/entrypoint-common.bst", stack["depends"])


if __name__ == "__main__":
    unittest.main()

"""Host-only countme checks: all HTTP and clocks are intercepted, never live pings."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import importlib.util
import http.client
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
import urllib.error


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "elements/printing/files/countme.py"
LIBRARY = ROOT / "elements/printing/files/entrypoint-common.sh"
APP = "ghostscript-printer-app"


def load_client():
    spec = importlib.util.spec_from_file_location("printer_countme", HELPER)
    client = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(client)
    return client


class Response(io.BytesIO):
    def __init__(self, body=b'{"success":true}', status=200):
        super().__init__(body)
        self.status = status


class CountmeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.state = Path(self.temporary.name)
        self.client = load_client()
        self.now = datetime(2026, 11, 14, 23, 59, tzinfo=timezone.utc)
        clock = self.enterContext(patch.object(self.client, "datetime"))
        clock.now.side_effect = lambda tz: self.now.astimezone(tz)
        self.transport = self.enterContext(patch("urllib.request.urlopen"))
        self.transport.side_effect = lambda *args, **kwargs: Response()

    def check(self, app=APP, state=None):
        return self.client.check_once(self.state if state is None else state, app)

    def test_daily_restart_rollover_deleted_marker_and_private_state(self):
        self.assertTrue(self.check())
        request = self.transport.call_args.args[0]
        self.assertEqual(request.full_url, "https://countme.projectbluefin.io/v1/ping")
        self.assertEqual(request.get_method(), "PUT")
        self.assertEqual(request.get_header("Content-type"), "application/json")
        self.assertEqual(json.loads(request.data), {"image": APP + "/main:unknown"})
        self.assertEqual(self.transport.call_args.kwargs, {"timeout": 10})
        lock_inode = (self.state / self.client.LOCK).stat().st_ino
        for name in (self.client.MARKER, self.client.LOCK):
            self.assertEqual(stat.S_IMODE((self.state / name).stat().st_mode), 0o600)
        restarted = load_client()
        with patch.object(restarted, "datetime", self.client.datetime):
            self.assertFalse(restarted.check_once(self.state, APP))
        self.now = datetime(2026, 11, 15, 0, 0, tzinfo=timezone.utc)
        self.assertTrue(self.check())
        self.assertEqual((self.state / self.client.MARKER).read_text(), "2026-11-15\n")
        self.now = datetime(2026, 11, 14, 12, 0, tzinfo=timezone.utc)
        self.assertFalse(self.check())  # Do not recount if the clock rolls back.
        (self.state / self.client.MARKER).unlink()
        self.assertTrue(self.check())  # State loss is explicitly allowed to recount.
        self.assertEqual(self.transport.call_count, 3)
        self.assertEqual((self.state / self.client.LOCK).stat().st_ino, lock_inode)

    def test_only_exact_supported_families(self):
        for app in sorted(self.client.APPS):
            with self.subTest(app=app), tempfile.TemporaryDirectory() as state:
                self.assertTrue(self.check(app=app, state=state))
                self.assertEqual(json.loads(self.transport.call_args.args[0].data),
                                 {"image": app + "/main:unknown"})
        self.transport.reset_mock()
        for app in ("", "cups", "Ghostscript-printer-app", APP + "/main:unknown", APP + "\n"):
            self.assertFalse(self.check(app=app))
        self.transport.assert_not_called()
        self.assertEqual(list(self.state.iterdir()), [])

    def test_rejected_non_json_and_network_failures_never_record_day(self):
        for body, status in ((b'{"success":false}', 200), (b'no JSON', 200),
                             (b'{"success":1}', 200), (b'[]', 200),
                             (b'{"success":true}', 201)):
            with self.subTest(body=body, status=status):
                self.transport.side_effect = lambda *a, **k: Response(body, status)
                self.assertFalse(self.check())
                self.assertFalse((self.state / self.client.MARKER).exists())
        for error in (urllib.error.URLError("offline"), TimeoutError("slow"),
                      http.client.IncompleteRead(b"partial"),
                      urllib.error.HTTPError("https://example.invalid", 500, "failed", {}, None)):
            with self.subTest(error=error):
                self.transport.side_effect = error
                self.assertFalse(self.check())
                self.assertFalse((self.state / self.client.MARKER).exists())
        self.transport.side_effect = lambda *a, **k: Response()
        self.assertTrue(self.check())

    def test_overlapping_same_volume_call_is_nonblocking_and_lock_inode_survives(self):
        entered, release = threading.Event(), threading.Event()

        def transport(*args, **kwargs):
            entered.set()
            if not release.wait(5):
                raise TimeoutError("test release missing")
            return Response()

        self.transport.side_effect = transport
        with ThreadPoolExecutor(max_workers=2) as workers:
            first = workers.submit(self.check)
            self.assertTrue(entered.wait(2))
            inode = (self.state / self.client.LOCK).stat().st_ino
            try:
                second = workers.submit(self.check)
                self.assertFalse(second.result(timeout=1))
            finally:
                release.set()
            self.assertTrue(first.result(timeout=2))
        self.assertEqual(self.transport.call_count, 1)
        self.assertEqual((self.state / self.client.LOCK).stat().st_ino, inode)
        self.assertFalse(self.check())

    def test_state_marker_and_lock_symlinks_and_nonregular_files_are_untouched(self):
        with tempfile.TemporaryDirectory() as outside:
            target = Path(outside) / "protected"
            target.write_text("keep this content")
            target.chmod(0o644)
            for name in (self.client.MARKER, self.client.LOCK):
                for kind in ("symlink", "fifo", "directory", "hardlink"):
                    with self.subTest(name=name, kind=kind), tempfile.TemporaryDirectory() as state:
                        entry = Path(state) / name
                        if kind == "symlink":
                            entry.symlink_to(target)
                        elif kind == "fifo":
                            os.mkfifo(entry)
                        elif kind == "directory":
                            entry.mkdir()
                        else:
                            os.link(target, entry)
                        self.assertFalse(self.check(state=state))
                        self.assertEqual(target.read_text(), "keep this content")
                        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o644)
            link = self.state / "state-link"
            link.symlink_to(outside, target_is_directory=True)
            self.assertFalse(self.check(state=link))
            self.assertFalse((Path(outside) / self.client.LOCK).exists())
            self.transport.assert_not_called()

    def test_opt_out_disabled_file_skips_transport_and_marker(self):
        disabled = self.state / self.client.DISABLED
        disabled.write_text("opt-out")
        self.assertFalse(self.check())
        self.assertFalse((self.state / self.client.MARKER).exists())
        self.transport.assert_not_called()

    def test_clock_read_write_and_lock_failures_are_noncritical(self):
        for obj, method in ((self.client.datetime, "now"), (self.client.os, "replace"),
                            (self.client.fcntl, "flock")):
            with self.subTest(method=method), patch.object(obj, method, side_effect=OSError("failed")):
                self.assertFalse(self.check())
                self.assertFalse((self.state / self.client.MARKER).exists())
        self.assertEqual(list(self.state.glob(".countme_day.*")), [])
        marker = self.state / self.client.MARKER
        marker.write_bytes(b"not a date\xff")
        self.transport.reset_mock()
        self.assertFalse(self.check())
        self.assertEqual(marker.read_bytes(), b"not a date\xff")
        self.transport.assert_not_called()
        marker.unlink()
        self.assertTrue(self.check())

    def test_loop_uses_four_hour_checks(self):
        with patch.object(self.client, "check_once") as check, \
             patch.object(self.client.time, "sleep", side_effect=[None, SystemExit]) as sleep, \
             patch.object(sys, "argv", [str(HELPER), str(self.state), APP]):
            with self.assertRaises(SystemExit):
                self.client.main()
        self.assertEqual(check.call_count, 2)
        check.assert_called_with(str(self.state), APP)
        self.assertEqual([call.args for call in sleep.call_args_list], [(14400,), (14400,)])

    def test_reporter_exit_and_sleep_do_not_own_printing_supervision(self):
        for mode in ("sleep", "exit", "startup-failure", "repeated-stop"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                binary, run, state = work / "bin", work / "run", work / "state"
                binary.mkdir()
                run.mkdir()
                state.mkdir()
                # Invoke the real helper through the public bash start function.
                # Patch urllib before runpy so even an accidental regression cannot ping production.
                wrapper = binary / "python3"
                wrapper.write_text(
                    f"#!{sys.executable}\n"
                    "import os, runpy, sys, urllib.request\n"
                    "def offline(*args, **kwargs): raise OSError('host-only test')\n"
                    "urllib.request.urlopen = offline\n"
                    f"sys.argv = [{str(HELPER)!r}, *sys.argv[2:]]\n"
                    "if os.environ['EARLY_EXIT'] == '1': sys.argv[2] = 'unsupported'\n"
                    "runpy.run_path(sys.argv[0], run_name='__main__')\n"
                )
                wrapper.chmod(0o755)
                daemon = binary / "daemon"
                daemon.write_text(
                    f"#!{sys.executable}\n"
                    "import os, pathlib, socket, sys, time\n"
                    "run = pathlib.Path(os.environ['RUN'])\n"
                    "name = pathlib.Path(sys.argv[0]).name\n"
                    "if name == 'dbus-daemon':\n"
                    "    listener = socket.socket(socket.AF_UNIX)\n"
                    "    listener.bind(str(run / 'dbus/system_bus_socket'))\n"
                    "elif name == 'avahi-daemon':\n"
                    "    (run / 'avahi-daemon/pid').write_text(str(os.getpid()))\n"
                    "else:\n"
                    "    time.sleep(0.3)\n"
                    "    sys.exit(37)\n"
                    "time.sleep(60)\n"
                )
                daemon.chmod(0o755)
                for name in ("dbus-daemon", "avahi-daemon", "printer"):
                    (binary / name).symlink_to(daemon)
                env = dict(os.environ, PATH=f"{binary}:{os.environ['PATH']}", RUN=str(run),
                           STATE=str(state), LIBRARY=str(LIBRARY), PIDFILE=str(work / "pid"),
                           EARLY_EXIT=str(int(mode == "exit")), MODE=mode)
                result = subprocess.run(
                    ["bash", "-euo", "pipefail", "-c", '''
source "$LIBRARY"
printer_app_stop_countme
printer_app_start_countme "$STATE" ghostscript-printer-app
printf '%s' "$printer_app_countme_pid" > "$PIDFILE"
if [[ "$MODE" == startup-failure ]]; then mkdir() { return 9; }; fi
if [[ "$MODE" == repeated-stop ]]; then
  printer_app_stop_countme
  printer_app_stop_countme
fi
printer_app_supervise "$RUN" printer
'''], env=env, capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(result.returncode, 9 if mode == "startup-failure" else 37, result.stderr)
                pid = int((work / "pid").read_text())
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)


if __name__ == "__main__":
    unittest.main()

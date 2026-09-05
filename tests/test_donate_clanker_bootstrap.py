"""The guest bootstrap keeps its half of the donate-clanker envelope contract.

`elements/podman-vm/files/donate-clanker-bootstrap.py` is installed into the
podman-vm guest, where nothing can reach it: the disk ships no SSH and no guest
agent, so a regression only surfaces as a VM that boots to a login prompt and
never registers with the Hive. These tests exercise the four pieces that carry
the contract -- `validate`, `worker_environment`, `read_envelope` and `main` --
on the host, before the element is ever built.
"""

import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).parents[1]
BOOTSTRAP = ROOT / "elements" / "podman-vm" / "files" / "donate-clanker-bootstrap.py"


def _load_bootstrap():
    """Import the guest script by path: its filename is not a Python name."""
    spec = importlib.util.spec_from_file_location(
        "donate_clanker_bootstrap", BOOTSTRAP
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


bootstrap = _load_bootstrap()


def valid_envelope(**overrides):
    envelope = {
        "version": 2,
        "hive_endpoint": "wss://hive.example/ws",
        "registration_token": "tok-123",
        "backend": "goose",
        "run_id": "run-42",
    }
    envelope.update(overrides)
    return envelope


class ProtocolConstantTests(unittest.TestCase):
    def test_guest_speaks_envelope_version_two(self):
        self.assertEqual(bootstrap.PROTOCOL_VERSION, 2)

    def test_required_fields_are_the_four_documented_ones(self):
        self.assertEqual(
            bootstrap.REQUIRED_FIELDS,
            ("hive_endpoint", "registration_token", "backend", "run_id"),
        )

    def test_envelope_timeout_outwaits_the_host_accept_timeout(self):
        # The launcher's accept timeout is 180s; giving up first turns a slow
        # guest boot into a failed handshake.
        self.assertGreater(bootstrap.ENVELOPE_TIMEOUT, 180.0)


class ValidateTests(unittest.TestCase):
    def test_accepts_a_minimal_version_two_envelope(self):
        self.assertIsNone(bootstrap.validate(valid_envelope()))

    def test_accepts_an_https_endpoint(self):
        bootstrap.validate(valid_envelope(hive_endpoint="https://hive.example"))

    def test_ignores_unknown_optional_fields(self):
        # More optional fields may be added by the launcher; the guest must not
        # demand an exact key set.
        bootstrap.validate(valid_envelope(some_future_field="whatever"))

    def test_rejects_a_non_object_envelope(self):
        with self.assertRaisesRegex(ValueError, "not a JSON object"):
            bootstrap.validate(["not", "an", "object"])

    def test_rejects_a_version_one_envelope(self):
        with self.assertRaisesRegex(ValueError, "unsupported bootstrap version"):
            bootstrap.validate(valid_envelope(version=1))

    def test_rejects_a_versionless_envelope(self):
        envelope = valid_envelope()
        del envelope["version"]
        with self.assertRaisesRegex(ValueError, "unsupported bootstrap version"):
            bootstrap.validate(envelope)

    def test_rejects_each_missing_required_field(self):
        for field in bootstrap.REQUIRED_FIELDS:
            with self.subTest(field=field):
                envelope = valid_envelope()
                del envelope[field]
                with self.assertRaisesRegex(ValueError, field):
                    bootstrap.validate(envelope)

    def test_rejects_each_empty_required_field(self):
        for field in bootstrap.REQUIRED_FIELDS:
            with self.subTest(field=field):
                with self.assertRaisesRegex(ValueError, field):
                    bootstrap.validate(valid_envelope(**{field: ""}))

    def test_reports_every_missing_field_at_once(self):
        envelope = valid_envelope()
        del envelope["backend"]
        del envelope["run_id"]
        with self.assertRaises(ValueError) as caught:
            bootstrap.validate(envelope)
        self.assertIn("backend", str(caught.exception))
        self.assertIn("run_id", str(caught.exception))

    def test_rejects_a_plaintext_endpoint(self):
        for endpoint in ("http://hive.example", "ws://hive.example", "hive.example"):
            with self.subTest(endpoint=endpoint):
                with self.assertRaisesRegex(ValueError, "invalid bootstrap endpoint"):
                    bootstrap.validate(valid_envelope(hive_endpoint=endpoint))


class WorkerEnvironmentTests(unittest.TestCase):
    """The worker reads these names and no others: a typo means no credentials."""

    def test_maps_the_endpoint_onto_both_names_the_worker_reads(self):
        env = bootstrap.worker_environment(valid_envelope())
        self.assertEqual(env["HIVE_WS_URL"], "wss://hive.example/ws")
        self.assertEqual(env["HIVE_HUB"], "wss://hive.example/ws")

    def test_maps_token_backend_and_run_id(self):
        env = bootstrap.worker_environment(valid_envelope())
        self.assertEqual(env["HIVE_REGISTRATION_TOKEN"], "tok-123")
        self.assertEqual(env["AGENT_BACKEND"], "goose")
        self.assertEqual(env["DONATE_CLANKER_RUN_ID"], "run-42")

    def test_goose_provider_defaults_to_github_copilot(self):
        env = bootstrap.worker_environment(valid_envelope())
        self.assertEqual(env["GOOSE_PROVIDER"], "github_copilot")

    def test_an_empty_goose_provider_still_falls_back(self):
        env = bootstrap.worker_environment(valid_envelope(goose_provider=""))
        self.assertEqual(env["GOOSE_PROVIDER"], "github_copilot")

    def test_an_explicit_goose_provider_wins(self):
        env = bootstrap.worker_environment(valid_envelope(goose_provider="openai"))
        self.assertEqual(env["GOOSE_PROVIDER"], "openai")

    def test_optional_model_and_secret_are_omitted_when_absent(self):
        env = bootstrap.worker_environment(valid_envelope())
        self.assertNotIn("GOOSE_MODEL", env)
        self.assertNotIn("GITHUB_COPILOT_TOKEN", env)

    def test_optional_model_and_secret_are_exported_when_present(self):
        env = bootstrap.worker_environment(
            valid_envelope(goose_model="gpt-5", provider_secret="ghu_secret")
        )
        self.assertEqual(env["GOOSE_MODEL"], "gpt-5")
        self.assertEqual(env["GITHUB_COPILOT_TOKEN"], "ghu_secret")

    def test_exports_no_name_the_worker_does_not_read(self):
        env = bootstrap.worker_environment(
            valid_envelope(goose_model="gpt-5", provider_secret="ghu_secret")
        )
        self.assertEqual(
            set(env),
            {
                "HIVE_WS_URL",
                "HIVE_HUB",
                "HIVE_REGISTRATION_TOKEN",
                "AGENT_BACKEND",
                "DONATE_CLANKER_RUN_ID",
                "GOOSE_PROVIDER",
                "GOOSE_MODEL",
                "GITHUB_COPILOT_TOKEN",
            },
        )

    def test_does_not_leak_the_raw_envelope_into_the_environment(self):
        env = bootstrap.worker_environment(valid_envelope(provider_secret="s3cret"))
        self.assertNotIn("provider_secret", env)
        self.assertNotIn("hive_endpoint", env)


class _ChannelFixture:
    """Point the module at a real file standing in for the virtio-serial port."""

    def __init__(self, test, contents=None, create=True):
        self.dir = tempfile.TemporaryDirectory()
        test.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "bootstrap-port")
        if create:
            with open(self.path, "w") as handle:
                if contents is not None:
                    handle.write(contents)
        patcher = mock.patch.object(bootstrap, "CHANNEL", self.path)
        patcher.start()
        test.addCleanup(patcher.stop)
        # Keep the retry loop from turning a unit test into a 240s wait.
        interval = mock.patch.object(bootstrap, "RETRY_INTERVAL", 0)
        interval.start()
        test.addCleanup(interval.stop)

    def read_back(self):
        with open(self.path) as handle:
            return handle.read()


class ReadEnvelopeTests(unittest.TestCase):
    def test_returns_the_first_line_the_host_wrote(self):
        channel = _ChannelFixture(
            self, json.dumps(valid_envelope()) + "\n" + '{"stray": true}\n'
        )
        handle, envelope = bootstrap.read_envelope(bootstrap.time.monotonic() + 5)
        with handle:
            self.assertEqual(envelope, valid_envelope())
        del channel

    def test_retries_until_the_port_appears(self):
        channel = _ChannelFixture(self, create=False)
        original_open = os.open
        calls = {"n": 0}

        def flaky_open(path, *args, **kwargs):
            if path == channel.path:
                calls["n"] += 1
                if calls["n"] < 3:
                    raise OSError(2, "No such file or directory")
                with open(path, "w") as handle:
                    handle.write(json.dumps(valid_envelope()) + "\n")
            return original_open(path, *args, **kwargs)

        with mock.patch.object(bootstrap.os, "open", flaky_open):
            handle, envelope = bootstrap.read_envelope(
                bootstrap.time.monotonic() + 5
            )
        with handle:
            self.assertEqual(envelope["run_id"], "run-42")
        self.assertGreaterEqual(calls["n"], 3)

    def test_an_empty_first_read_is_not_fatal(self):
        # The guest and the launcher race; treating EOF as fatal is what left
        # every VM launch sitting inert at a login prompt.
        channel = _ChannelFixture(self, "")
        state = {"written": False}
        real_monotonic = bootstrap.time.monotonic

        def write_once(_seconds):
            if not state["written"]:
                state["written"] = True
                with open(channel.path, "w") as handle:
                    handle.write(json.dumps(valid_envelope()) + "\n")

        with mock.patch.object(bootstrap.time, "sleep", write_once):
            handle, envelope = bootstrap.read_envelope(real_monotonic() + 5)
        with handle:
            self.assertEqual(envelope["backend"], "goose")
        self.assertTrue(state["written"])

    def test_a_blank_line_is_treated_as_no_envelope(self):
        _ChannelFixture(self, "\n")
        with self.assertRaises(TimeoutError):
            bootstrap.read_envelope(bootstrap.time.monotonic() + 0.2)

    def test_times_out_with_the_reason_the_port_could_not_be_opened(self):
        _ChannelFixture(self, create=False)
        with self.assertRaises(TimeoutError) as caught:
            bootstrap.read_envelope(bootstrap.time.monotonic() + 0.2)
        self.assertIn("No such file or directory", str(caught.exception))
        self.assertIn(bootstrap.CHANNEL, str(caught.exception))

    def test_times_out_with_the_reason_the_host_stayed_silent(self):
        _ChannelFixture(self, "")
        with self.assertRaises(TimeoutError) as caught:
            bootstrap.read_envelope(bootstrap.time.monotonic() + 0.2)
        self.assertIn("has not written its envelope yet", str(caught.exception))

    def test_a_past_deadline_never_opens_the_channel(self):
        _ChannelFixture(self, json.dumps(valid_envelope()) + "\n")
        with mock.patch.object(bootstrap.os, "open") as opener:
            with self.assertRaises(TimeoutError) as caught:
                bootstrap.read_envelope(bootstrap.time.monotonic() - 1)
        opener.assert_not_called()
        self.assertIn("the port never appeared", str(caught.exception))

    def test_malformed_json_surfaces_as_a_decode_error(self):
        _ChannelFixture(self, "not json at all\n")
        with self.assertRaises(json.JSONDecodeError):
            bootstrap.read_envelope(bootstrap.time.monotonic() + 5)


class LogTests(unittest.TestCase):
    def test_writes_a_prefixed_line_to_stderr(self):
        stderr = io.StringIO()
        with mock.patch.object(bootstrap.sys, "stderr", stderr):
            with mock.patch("builtins.open", mock.mock_open()):
                bootstrap.log("hello")
        self.assertEqual(stderr.getvalue(), "donate-clanker-bootstrap: hello\n")

    def test_mirrors_the_line_to_dev_kmsg(self):
        # tests/vm-boot.sh asserts on this /dev/kmsg line to prove systemd ran
        # the unit; console output alone stops arriving after TTYVHangup.
        opener = mock.mock_open()
        with mock.patch.object(bootstrap.sys, "stderr", io.StringIO()):
            with mock.patch("builtins.open", opener):
                bootstrap.log("hello")
        opener.assert_called_once_with("/dev/kmsg", "w")
        opener().write.assert_called_once_with("donate-clanker-bootstrap: hello\n")

    def test_an_unwritable_kmsg_is_not_fatal(self):
        with mock.patch.object(bootstrap.sys, "stderr", io.StringIO()):
            with mock.patch("builtins.open", side_effect=OSError("read-only")):
                bootstrap.log("hello")


class MainHandshakeTests(unittest.TestCase):
    def setUp(self):
        self.stderr = mock.patch.object(bootstrap.sys, "stderr", io.StringIO())
        self.stderr.start()
        self.addCleanup(self.stderr.stop)
        kmsg = mock.patch.object(bootstrap, "log", lambda message: None)
        kmsg.start()
        self.addCleanup(kmsg.stop)

    def test_acks_the_envelope_and_execs_the_worker(self):
        channel = _ChannelFixture(self, json.dumps(valid_envelope()) + "\n")
        execs = []
        with mock.patch.dict(os.environ, {}, clear=False):
            with mock.patch.object(
                bootstrap.os, "execv", lambda path, argv: execs.append((path, argv))
            ):
                bootstrap.main()
            self.assertEqual(
                execs, [(bootstrap.WORKER, [bootstrap.WORKER])]
            )
            self.assertEqual(os.environ["HIVE_WS_URL"], "wss://hive.example/ws")
            self.assertEqual(os.environ["AGENT_BACKEND"], "goose")

        ack = json.loads(channel.read_back().splitlines()[1])
        self.assertEqual(ack, {"version": 2, "type": "control_ack"})

    def test_an_invalid_envelope_is_never_acked_and_never_execs(self):
        channel = _ChannelFixture(
            self, json.dumps(valid_envelope(hive_endpoint="http://hive")) + "\n"
        )
        with mock.patch.object(bootstrap.os, "execv") as execv:
            with self.assertRaisesRegex(ValueError, "invalid bootstrap endpoint"):
                bootstrap.main()
        execv.assert_not_called()
        self.assertNotIn("control_ack", channel.read_back())

    def test_a_rejected_envelope_exports_no_worker_credentials(self):
        _ChannelFixture(self, json.dumps(valid_envelope(version=1)) + "\n")
        with mock.patch.dict(os.environ, {}, clear=False):
            with mock.patch.object(bootstrap.os, "execv"):
                with self.assertRaises(ValueError):
                    bootstrap.main()
            self.assertNotIn("HIVE_REGISTRATION_TOKEN", os.environ)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/python3
"""Consume the donate-clanker bootstrap envelope, then exec the guest worker.

Contract, both ends of it, as implemented by the only consumer
(projectbluefin/donate-clanker's `just/61-donate-clanker.just`):

Host side. The launcher binds a host-local unix socket, QEMU connects to it as
a chardev client, and the guest sees that chardev as the virtio-serial port
named below. The launcher writes exactly one newline-terminated JSON object --
a *version 2* envelope -- and then waits for a version 2 `control_ack` before
it considers the guest bootstrapped. Version 2 carries four required fields and
three optional ones; more optional fields may be added, so validate the
required set and ignore the rest instead of demanding an exact key set.

Worker side. `/usr/libexec/donate-clanker-worker` (donate-clanker's
`cmd/contributor`) reads its Hive credentials from the environment first and
only then from a mounted `contributor.env`. The names it reads are
`HIVE_WS_URL`/`HIVE_HUB`, `HIVE_REGISTRATION_TOKEN`, `AGENT_BACKEND`,
`GOOSE_PROVIDER`, `GOOSE_MODEL` and `GITHUB_COPILOT_TOKEN`. Exporting anything
else leaves the worker with no credentials at all.

Progress is written to stderr for the journal, and mirrored to /dev/kmsg so it
reaches the serial console. That mirror is not decoration: this guest has no
SSH and no guest agent, and a unit's `console` output stream stops reaching the
serial console once `serial-getty` has done its `TTYVHangup` -- measured on the
published 25.08.15 disk, where a `StandardOutput=journal+console` unit's output
never appeared on the console while a /dev/kmsg write from the same boot did.
tests/vm-boot.sh asserts on the /dev/kmsg line to prove systemd really ran this.
"""
import json
import os
import sys
import time

CHANNEL = "/dev/virtio-ports/org.projectbluefin.donate-clanker.bootstrap"
WORKER = "/usr/libexec/donate-clanker-worker"
PROTOCOL_VERSION = 2

# The host's accept timeout defaults to 180s. Outwaiting it keeps a slow guest
# boot from being the reason the handshake fails; the unit's TimeoutStartSec is
# set above this so systemd does not kill the wait first.
ENVELOPE_TIMEOUT = 240.0
RETRY_INTERVAL = 1.0

REQUIRED_FIELDS = ("hive_endpoint", "registration_token", "backend", "run_id")

LOG_PREFIX = "donate-clanker-bootstrap:"


def log(message):
    line = f"{LOG_PREFIX} {message}"
    print(line, file=sys.stderr, flush=True)
    try:
        with open("/dev/kmsg", "w") as kmsg:
            kmsg.write(line + "\n")
    except OSError:
        pass


def read_envelope(deadline):
    """Return the first envelope line the host writes to the channel.

    The guest and the launcher race: the port may not exist yet, and once it
    does a read can return EOF because the host has not written its single
    line. Neither is fatal and neither is retried by systemd -- this is a
    `oneshot` with no `Restart=` -- so both are retried here until the
    deadline. Treating the first empty read as fatal is what made every VM
    launch end with an inert guest sitting at a login prompt.
    """
    last_error = "the port never appeared"
    while time.monotonic() < deadline:
        try:
            fd = os.open(CHANNEL, os.O_RDWR | os.O_CLOEXEC)
        except OSError as exc:
            last_error = str(exc)
            time.sleep(RETRY_INTERVAL)
            continue
        channel = os.fdopen(fd, "r+b", buffering=0)
        line = channel.readline(65536)
        if not line.strip():
            last_error = "the host has not written its envelope yet"
            channel.close()
            time.sleep(RETRY_INTERVAL)
            continue
        return channel, json.loads(line.decode("utf-8"))
    raise TimeoutError(
        f"no bootstrap envelope on {CHANNEL} within "
        f"{ENVELOPE_TIMEOUT:.0f}s ({last_error})"
    )


def validate(envelope):
    if not isinstance(envelope, dict):
        raise ValueError("bootstrap envelope is not a JSON object")
    if envelope.get("version") != PROTOCOL_VERSION:
        raise ValueError(
            f"unsupported bootstrap version {envelope.get('version')!r} "
            f"(this guest speaks version {PROTOCOL_VERSION})"
        )
    missing = [key for key in REQUIRED_FIELDS if not envelope.get(key)]
    if missing:
        raise ValueError(f"incomplete bootstrap envelope: missing {', '.join(missing)}")
    if not envelope["hive_endpoint"].startswith(("https://", "wss://")):
        raise ValueError("invalid bootstrap endpoint")


def worker_environment(envelope):
    """Map the envelope onto the names the worker actually reads."""
    env = {
        "HIVE_WS_URL": envelope["hive_endpoint"],
        "HIVE_HUB": envelope["hive_endpoint"],
        "HIVE_REGISTRATION_TOKEN": envelope["registration_token"],
        "AGENT_BACKEND": envelope["backend"],
        "DONATE_CLANKER_RUN_ID": envelope["run_id"],
        "GOOSE_PROVIDER": envelope.get("goose_provider") or "github_copilot",
    }
    if envelope.get("goose_model"):
        env["GOOSE_MODEL"] = envelope["goose_model"]
    if envelope.get("provider_secret"):
        env["GITHUB_COPILOT_TOKEN"] = envelope["provider_secret"]
    return env


def main():
    log(f"waiting for the host bootstrap envelope on {CHANNEL}")
    channel, envelope = read_envelope(time.monotonic() + ENVELOPE_TIMEOUT)
    with channel:
        validate(envelope)
        channel.write(
            (
                json.dumps({"version": PROTOCOL_VERSION, "type": "control_ack"})
                + "\n"
            ).encode("utf-8")
        )
    log(f"envelope accepted for run {envelope['run_id']}, starting the worker")
    os.environ.update(worker_environment(envelope))
    os.execv(WORKER, [WORKER])


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        log(f"failed: {exc}")
        raise SystemExit(1)

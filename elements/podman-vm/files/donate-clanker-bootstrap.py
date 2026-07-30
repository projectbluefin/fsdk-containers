#!/usr/bin/python3
import json
import os
import sys
import time

CHANNEL = "/dev/virtio-ports/org.projectbluefin.donate-clanker.bootstrap"
WORKER = "/usr/libexec/donate-clanker-worker"


def main():
    for _ in range(120):
        try:
            channel = open(CHANNEL, "r+", encoding="utf-8")
            break
        except FileNotFoundError:
            time.sleep(1)
    else:
        raise FileNotFoundError(CHANNEL)
    with channel:
        envelope = json.loads(channel.readline(65536))
        if set(envelope) != {"version", "hive_endpoint", "registration_token", "backend", "run_id"}:
            raise ValueError("invalid bootstrap envelope")
        if envelope["version"] != 1:
            raise ValueError("unsupported bootstrap version")
        if not envelope["hive_endpoint"].startswith(("https://", "wss://")):
            raise ValueError("invalid bootstrap endpoint")
        if not all(envelope[key] for key in ("registration_token", "backend", "run_id")):
            raise ValueError("incomplete bootstrap envelope")
        channel.write(json.dumps({"version": 1, "type": "control_ack"}) + "\n")
        channel.flush()
    os.environ["DONATE_CLANKER_HIVE_ENDPOINT"] = envelope["hive_endpoint"]
    os.environ["DONATE_CLANKER_REGISTRATION_TOKEN"] = envelope["registration_token"]
    os.environ["DONATE_CLANKER_BACKEND"] = envelope["backend"]
    os.environ["DONATE_CLANKER_RUN_ID"] = envelope["run_id"]
    os.execv(WORKER, [WORKER])


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"donate-clanker bootstrap failed: {exc}", file=sys.stderr)
        raise SystemExit(1)

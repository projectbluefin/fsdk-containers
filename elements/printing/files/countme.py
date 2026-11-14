#!/usr/bin/env python3
"""Best-effort daily active printer-app installation reporting; no host identity."""

from datetime import date, datetime, timezone
import fcntl
import json
import os
import secrets
import stat
import sys
import time
import urllib.request


APPS = frozenset((
    "ghostscript-printer-app", "hplip-printer-app",
    "gutenprint-printer-app", "ps-printer-app",
))
MARKER = ".countme_day"
DISABLED = ".countme_disabled"
LOCK = ".countme.lock"
CHECK_INTERVAL = 4 * 60 * 60


def check_once(state, app):
    """Return true only for an acknowledged, locally recorded daily report."""
    if app not in APPS:
        return False
    try:
        directory = os.open(state, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            # Never unlink/replace this inode: every overlapping client locks it.
            lock_fd = os.open(
                LOCK, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK,
                0o600, dir_fd=directory,
            )
            with os.fdopen(lock_fd, "rb") as lock:
                info = os.fstat(lock.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                    return False
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                if not os.path.samestat(info, os.stat(
                    LOCK, dir_fd=directory, follow_symlinks=False,
                )):
                    return False
                os.fchmod(lock.fileno(), 0o600)
                try:
                    dis_fd = os.open(
                        DISABLED, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                        dir_fd=directory,
                    )
                    os.close(dis_fd)
                    return False
                except FileNotFoundError:
                    pass
                day = datetime.now(timezone.utc).date().isoformat()
                try:
                    marker_fd = os.open(
                        MARKER, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                        dir_fd=directory,
                    )
                except FileNotFoundError:
                    previous = None
                else:
                    with os.fdopen(marker_fd, "rb") as marker:
                        info = os.fstat(marker.fileno())
                        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                            return False
                        previous = marker.read(32).decode("ascii").strip()
                        if date.fromisoformat(previous).isoformat() != previous:
                            return False
                # A clock moving backwards must not recount an earlier day.
                if previous is not None and previous >= day:
                    return False
                request = urllib.request.Request(
                    "https://countme.projectbluefin.io/v1/ping",
                    data=json.dumps({"image": f"{app}/main:unknown"}).encode("ascii"),
                    headers={"Content-Type": "application/json"}, method="PUT",
                )
                # urllib's default HTTPS context verifies certificates/hostnames.
                with urllib.request.urlopen(request, timeout=10) as response:
                    if response.status != 200:
                        return False
                    acknowledgement = json.loads(response.read(4096))
                    if not isinstance(acknowledgement, dict) or acknowledgement.get("success") is not True:
                        return False
                temporary = f"{MARKER}.{secrets.token_hex(8)}"
                try:
                    marker_fd = os.open(
                        temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                        0o600, dir_fd=directory,
                    )
                    with os.fdopen(marker_fd, "wb") as marker:
                        marker.write((day + "\n").encode("ascii"))
                        marker.flush()
                        os.fsync(marker.fileno())
                    os.replace(temporary, MARKER, src_dir_fd=directory, dst_dir_fd=directory)
                    os.fsync(directory)
                finally:
                    try:
                        os.unlink(temporary, dir_fd=directory)
                    except FileNotFoundError:
                        pass
                return True
        finally:
            os.close(directory)
    except Exception:
        # Telemetry is never a reason to interrupt printing, including bad clocks,
        # unavailable state/locks, partial HTTP responses or failed marker writes.
        return False


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in APPS:
        return
    while True:
        check_once(sys.argv[1], sys.argv[2])
        # One direct Python child, not a shell loop with an orphanable sleeper.
        # Default SIGTERM handling also interrupts in-flight network operations.
        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    main()

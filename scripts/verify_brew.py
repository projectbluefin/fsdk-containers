#!/usr/bin/env python3
"""Verify both exported Brew machine formats, never just archive path names."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tarfile
import tempfile


REQUIRED = (
    "usr/bin/bash", "usr/bin/git", "usr/bin/curl", "usr/bin/patchelf",
    "usr/bin/dbus-daemon", "usr/bin/systemd-run", "usr/bin/systemctl",
    "usr/lib/systemd/systemd", "usr/lib/systemd/systemd-logind",
    "usr/lib/systemd/system/dbus.service", "usr/lib/systemd/system/dbus.socket",
    "usr/lib/systemd/system/user@.service", "usr/lib/systemd/user/dbus.service",
    "usr/lib/systemd/user/dbus.socket", "etc/pam.d/systemd-user",
    "etc/passwd", "etc/group", "etc/shadow", "etc/nsswitch.conf",
    "etc/machine-id", "etc/locale.conf", "etc/subuid", "etc/subgid",
)


def in_root(root, path):
    """Resolve guest absolute symlinks in the guest root, never in the host."""
    parts = list(Path(path).parts)
    if parts and parts[0] == "/":
        parts.pop(0)
    resolved = []
    links = 0
    while parts:
        part = parts.pop(0)
        if part in ("", "."):
            continue
        if part == "..":
            if not resolved:
                raise ValueError("guest symlink escapes root")
            resolved.pop()
            continue
        candidate = root.joinpath(*resolved, part)
        if candidate.is_symlink():
            links += 1
            if links > 40:
                raise ValueError("guest symlink loop")
            target = os.readlink(candidate)
            target_parts = list(Path(target).parts)
            if target.startswith("/"):
                resolved = []
                target_parts.pop(0)
            parts = target_parts + parts
        else:
            resolved.append(part)
    return root.joinpath(*resolved)


def verify_checksums(directory, version):
    names = {f"homebrew-env-{version}.{format}.zst" for format in ("raw", "tar")}
    recorded = {}
    for line in (directory / "SHA256SUMS").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64}) [ *]([^/]+)", line)
        if not match or match[2] in recorded:
            raise ValueError("malformed or duplicate checksum")
        recorded[match[2]] = match[1]
    if set(recorded) != names:
        raise ValueError("checksums must cover exactly both raw and tar outputs")
    for name in names:
        with (directory / name).open("rb") as source:
            if hashlib.file_digest(source, "sha256").hexdigest() != recorded[name]:
                raise ValueError(f"checksum mismatch: {name}")


def required_dlopen(program):
    """Read UAPI.12 FDO notes, independent of readelf's note pretty-printer."""
    sections = subprocess.check_output(["readelf", "-W", "-S", str(program)], text=True)
    with program.open("rb") as source:
        ident = source.read(16)
        endian = "<" if ident[5] == 1 else ">"
        for offset, size in re.findall(
            r"\[\s*\d+\]\s+\S+\s+NOTE\s+[0-9a-fA-F]+\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)", sections
        ):
            source.seek(int(offset, 16))
            notes = source.read(int(size, 16))
            position = 0
            while position + 12 <= len(notes):
                namesize, descsize, kind = struct.unpack_from(endian + "III", notes, position)
                name_start = position + 12
                desc_start = name_start + ((namesize + 3) & ~3)
                position = desc_start + ((descsize + 3) & ~3)
                if position > len(notes):
                    raise ValueError(f"truncated ELF note: {program}")
                if kind != 0x407C0C0A or notes[name_start:name_start + namesize] != b"FDO\0":
                    continue
                entries = json.loads(notes[desc_start:desc_start + descsize].rstrip(b"\0"))
                for entry in entries:
                    if entry.get("priority") == "required":
                        yield entry["soname"]


def verify_elf(root, programs):
    libraries = {}
    for library in (root / "usr/lib").rglob("*.so*"):
        libraries.setdefault(library.name, []).append(library)
    seen = set()
    queue = list(programs)
    while queue:
        program = in_root(root, queue.pop().relative_to(root))
        if program in seen:
            continue
        seen.add(program)
        with program.open("rb") as source:
            if source.read(4) != b"\x7fELF":
                continue
        dynamic = subprocess.check_output(["readelf", "-d", str(program)], text=True)
        headers = subprocess.check_output(["readelf", "-l", str(program)], text=True)
        for interpreter in re.findall(r"Requesting program interpreter: ([^\]]+)", headers):
            if not in_root(root, interpreter).is_file():
                raise ValueError(f"missing interpreter {interpreter}: {program}")
        for dependency in re.findall(r"Shared library: \[([^\]]+)\]", dynamic):
            candidates = libraries.get(dependency, [])
            if not candidates:
                raise ValueError(f"missing library {dependency}: {program}")
            queue.append(candidates[0])
        for alternatives in required_dlopen(program):
            # A soname list specifies alternatives, not cumulative dependencies.
            candidates = next((libraries[name] for name in alternatives if name in libraries), None)
            if not candidates:
                raise ValueError(f"missing required dlopen library {' or '.join(alternatives)}: {program}")
            queue.append(candidates[0])


def verify_root(root, version, commit, raw=True):
    for name in REQUIRED:
        if not in_root(root, name).is_file():
            raise ValueError(f"missing guest prerequisite: {name}")
    if in_root(root, "sbin/init") != in_root(root, "usr/lib/systemd/systemd"):
        raise ValueError("init must resolve to guest systemd")
    if (root / "etc/machine-id").read_bytes():
        raise ValueError("machine-id must be empty")
    if (root / "etc/locale.conf").read_text().strip() != "LANG=C.UTF-8":
        raise ValueError("missing UTF-8 locale")
    if "linuxbrew:x:1001:1001:" not in (root / "etc/passwd").read_text():
        raise ValueError("missing nonroot linuxbrew user")
    if "passwd: files systemd" not in (root / "etc/nsswitch.conf").read_text():
        raise ValueError("guest NSS must resolve systemd users")
    if "pam_systemd.so" not in in_root(root, "etc/pam.d/systemd-user").read_text():
        raise ValueError("guest PAM must initialize user sessions")
    seed = root / ("usr/share/bluefin/homebrew-seed" if raw else "home/linuxbrew/.linuxbrew")
    brew = seed / "Homebrew"
    if not (brew / ".git").is_dir():
        raise ValueError("missing real upstream Git repository")
    git = lambda *args: subprocess.check_output(["git", "-C", str(brew), *args], text=True).strip()
    if git("rev-parse", "HEAD") != commit or git("rev-parse", f"{version}^{{commit}}") != commit:
        raise ValueError("seed Git identity is not the pinned upstream release")
    git("fsck", "--connectivity-only", "--no-dangling")
    if git("remote", "get-url", "origin") != "https://github.com/Homebrew/brew.git":
        raise ValueError("seed origin does not permit upstream brew update")
    if git("config", "remote.origin.fetch") != "+refs/heads/*:refs/remotes/origin/*":
        raise ValueError("seed lacks upstream fetch refspec")
    if git("symbolic-ref", "HEAD") != "refs/heads/main":
        raise ValueError("seed must have an updatable upstream branch")
    ruby_version = (brew / "Library/Homebrew/vendor/portable-ruby-version").read_text().strip()
    portable = brew / "Library/Homebrew/vendor/portable-ruby"
    if os.readlink(portable / "current") != ruby_version:
        raise ValueError("portable Ruby current does not match pinned brew")
    ruby = portable / ruby_version / "bin/ruby"
    if not ruby.is_file() or not ruby.stat().st_mode & 0o111:
        raise ValueError("missing runnable matching portable Ruby")
    if os.readlink(seed / "bin/brew") != "../Homebrew/bin/brew":
        raise ValueError("brew entrypoint is not canonical")
    if list((seed / "Cellar").iterdir()):
        raise ValueError("producer must not install formulae")
    if raw and list((root / "home/linuxbrew/.linuxbrew").iterdir()):
        raise ValueError("raw prefix mountpoint must not duplicate seed")
    nss = list((root / "usr/lib").rglob("libnss_systemd.so.2"))
    pam = list((root / "usr/lib").rglob("pam_systemd.so"))
    if not nss or not pam:
        raise ValueError("missing NSS/PAM modules for guest user scopes")
    programs = [root / name for name in REQUIRED if name.startswith("usr/")]
    # DT_NEEDED from PID1 alone cannot cover separately shipped boot helpers.
    programs += [path for path in (root / "usr/lib/systemd").rglob("*") if path.is_file()]
    programs += [path for path in (root / "usr/bin").glob("systemd*") if path.is_file()]
    verify_elf(root, programs + nss + pam + [ruby] + list(portable.rglob("*.so")))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("version")
    parser.add_argument("commit")
    args = parser.parse_args()
    verify_checksums(args.directory, args.version)
    with tempfile.TemporaryDirectory(prefix="brew-artifacts-") as directory:
        temporary = Path(directory)
        for format in ("tar", "raw"):
            archive = temporary / f"machine.{format}"
            with archive.open("wb") as output:
                subprocess.run(["zstd", "-dc", str(args.directory / f"homebrew-env-{args.version}.{format}.zst")],
                               stdout=output, check=True)
            root = temporary / format
            root.mkdir()
            if format == "tar":
                with tarfile.open(archive) as tar:
                    tar.extractall(root, filter=tarfile.tar_filter)
            else:
                subprocess.run(["fsck.erofs", f"--extract={root}", str(archive)], check=True)
            verify_root(root, args.version, args.commit, raw=format == "raw")
    print("Brew tar/raw contracts verified: Git identity, Ruby, init, bus, PAM/NSS, ELF closure")


if __name__ == "__main__":
    main()

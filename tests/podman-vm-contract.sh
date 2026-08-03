#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
config="${repo_root}/elements/podman-vm/donate-clanker-vm-config.bst"
worker_source="${repo_root}/elements/podman-vm/files/donate-clanker-worker.source"
efi="${repo_root}/elements/podman-vm/podman-vm-efi.bst"
bootstrap="${repo_root}/elements/podman-vm/files/donate-clanker-bootstrap.py"

worker_commit=$(sed -n 's/^commit=//p' "${worker_source}")
[ "${worker_commit}" = "96cc69f5779d63b908d5f53957287b7ef6bda7fa" ]

grep -Fq "ref: ${worker_commit}" "${config}"
grep -Fq 'donate-clanker/image/config/goose.yaml' "${config}"
grep -Fq 'donate-clanker/image/config/local-agent-policy.md' "${config}"
grep -Fq 's/root=UUID=[0-9A-Fa-f-]+/root=UUID=${uuid_root}/g' "${efi}"
grep -Fq 'os.fdopen(fd, "r+b", buffering=0)' "${bootstrap}"
grep -Fq 'channel.write(' "${bootstrap}"

printf '%s\n' 'podman-vm guest contract checks passed'

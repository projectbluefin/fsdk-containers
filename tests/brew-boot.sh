#!/bin/bash
# Integration contract: invoke only on a systemd host, explicitly as root.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'brew-boot requires root on a systemd host' >&2; exit 1; }
archive=$(realpath "$1")
work=$(mktemp -d /var/tmp/brew-boot.XXXXXX)
machine="brew-contract-$$"
unit="$machine.service"
cleanup() {
    systemctl stop "$unit" >/dev/null 2>&1 || true
    systemctl reset-failed "$unit" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT
zstd -dc "$archive" > "$work/machine.raw"
mkdir -p "$work/root" "$work/home" "$work/prefix"
fsck.erofs --extract="$work/root" "$work/machine.raw"
cp -a "$work/root/usr/share/bluefin/homebrew-seed/." "$work/prefix/"
chown -R 1001:1001 "$work/home" "$work/prefix"
systemd-run --quiet --unit="$machine" --property=Type=notify --property=Delegate=yes \
    -- /usr/bin/systemd-nspawn --quiet --boot --machine="$machine" --image="$work/machine.raw" \
    --private-users=no --private-network --volatile=overlay \
    --bind="$work/home:/home/linuxbrew" --bind="$work/prefix:/home/linuxbrew/.linuxbrew"
ready=false
for ((i=0; i<60; i++)); do
    if systemd-run --quiet --pipe --wait --machine="$machine" -- /usr/bin/systemctl is-active systemd-logind.service >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 1
done
[[ $ready == true ]] || { journalctl -u "$unit" --no-pager >&2; exit 1; }
# No external network exists. A missing/incorrect interpreter cannot silently download.
systemd-run --quiet --pipe --wait --machine="$machine" --uid=1001 \
    --setenv=HOME=/home/linuxbrew --setenv=HOMEBREW_NO_ANALYTICS=1 \
    -- /home/linuxbrew/.linuxbrew/Homebrew/Library/Homebrew/vendor/portable-ruby/current/bin/ruby --version
prefix=$(systemd-run --quiet --pipe --wait --machine="$machine" --uid=1001 \
    --setenv=HOME=/home/linuxbrew -- /home/linuxbrew/.linuxbrew/bin/brew --prefix)
[[ $prefix == /home/linuxbrew/.linuxbrew ]]
# A user-manager service runs in the guest; a remote --scope executes locally.
systemd-run --quiet --pipe --wait --machine="$machine" -- /usr/bin/systemctl start user@1001.service
systemd-run --quiet --pipe --wait --expand-environment=no --user --machine="linuxbrew@$machine" --working-directory=/home/linuxbrew \
    -- /usr/bin/bash -c '[[ "$PWD" == /home/linuxbrew && "$(id -u)" == 1001 && "$1" == '\''arg with spaces;$HOME'\'' ]]' bash 'arg with spaces;$HOME'
set +e
systemd-run --quiet --pipe --wait --expand-environment=no --user --machine="linuxbrew@$machine" --working-directory=/home/linuxbrew \
    -- /usr/bin/bash -c 'exit 37'
status=$?
set -e
[[ $status == 37 ]] || { echo "guest user service lost exit code: $status" >&2; exit 1; }
# Shared prefix really belongs to the nonroot guest, not root.
systemd-run --quiet --pipe --wait --machine="$machine" --uid=1001 -- /usr/bin/touch /home/linuxbrew/.linuxbrew/.write-contract
[[ $(stat -c %u "$work/prefix/.write-contract") == 1001 ]]
echo 'Brew raw boots offline with logind, Ruby, nonroot writes, and guest user services'

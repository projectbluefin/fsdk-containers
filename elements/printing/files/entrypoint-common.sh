#!/usr/bin/env bash
# Source from a bash entrypoint using set -euo pipefail. No work runs on source.
# Public API and consumer example: docs/skills/printing-base.md, rule 8.

printer_app_usage_error() { printf '%s\n' "$1" >&2; exit 64; }
printer_app_config_error() { printf '%s\n' "$1" >&2; exit 78; }

# Validate before touching state. $1: built-in SYSTEM_NAME; $2: minimum port.
# Produces printer_app_args, to append to the application's own argument array.
printer_app_validate() {
  local system_name="$1" floor="${2:-1}" port option instance
  local -a requested=()
  printer_app_args=()
  if [[ ! "$floor" =~ ^[1-9][0-9]{0,4}$ ]] || ((floor > 65535)); then
    printer_app_usage_error 'minimum port must be between 1 and 65535'
  fi
  if [[ -n "${PORT:-}" ]]; then
    [[ "$PORT" =~ ^[0-9]+$ ]] || printer_app_usage_error 'PORT must be numeric'
    # Bound before arithmetic; strip leading zeros and always interpret decimal.
    [[ "$PORT" =~ ^0*([0-9]{1,5})$ ]] \
      || printer_app_usage_error "PORT must be between $floor and 65535"
    port=$((10#${BASH_REMATCH[1]}))
    ((port >= floor && port <= 65535)) \
      || printer_app_usage_error "PORT must be between $floor and 65535"
    printer_app_args+=(-o "server-port=$port")
  fi
  if [[ -n "${PRINTER_APP_SERVER_OPTIONS:-}" ]]; then
    [[ "$PRINTER_APP_SERVER_OPTIONS" =~ ^[a-z-]+(,[a-z-]+)*$ ]] \
      || printer_app_usage_error 'PRINTER_APP_SERVER_OPTIONS must be a comma-separated list of PAPPL server options'
    IFS=, read -r -a requested <<< "$PRINTER_APP_SERVER_OPTIONS"
    for option in "${requested[@]}"; do
      [[ "$option" == no-web-interface ]] \
        || printer_app_usage_error "PRINTER_APP_SERVER_OPTIONS contains unsupported option '$option'; supported: no-web-interface"
    done
    printer_app_args+=(-o "server-options=$PRINTER_APP_SERVER_OPTIONS")
  fi
  # Validate both syntaxes before checking capability, independent of host files.
  if [[ -n "${PRINTER_APP_AUTH_SERVICE:-}" ]]; then
    [[ "$PRINTER_APP_AUTH_SERVICE" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] \
      || printer_app_usage_error 'PRINTER_APP_AUTH_SERVICE must be a PAM service name'
  fi
  if [[ -n "${PRINTER_APP_ADMIN_GROUP:-}" ]]; then
    [[ "$PRINTER_APP_ADMIN_GROUP" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] \
      || printer_app_usage_error 'PRINTER_APP_ADMIN_GROUP must be a group name'
  fi
  if [[ -n "${PRINTER_APP_AUTH_SERVICE:-}" ]]; then
    printer_app_config_error 'PRINTER_APP_AUTH_SERVICE cannot be honoured (PAPPL is built without PAM); set PRINTER_APP_SERVER_OPTIONS=no-web-interface to disable web administration instead'
  fi
  if [[ -n "${PRINTER_APP_ADMIN_GROUP:-}" ]]; then
    printer_app_config_error 'PRINTER_APP_ADMIN_GROUP requires PRINTER_APP_AUTH_SERVICE; a group cannot be enforced without authentication'
  fi
  if [[ -n "${PRINTER_APP_INSTANCE:-}" ]]; then
    # ASCII only, independent of the container's locale; PAPPL quotes spaces.
    local LC_ALL=C
    instance="${PRINTER_APP_INSTANCE//[^A-Za-z0-9_-]/-}"
    while [[ "$instance" == *--* ]]; do instance="${instance//--/-}"; done
    instance="${instance#-}"; instance="${instance%-}"
    instance="${instance:0:24}"; instance="${instance%-}"
    [[ -n "$instance" ]] || printer_app_usage_error 'PRINTER_APP_INSTANCE must contain at least one letter, digit or underscore'
    printer_app_args+=(-o "system-name='$system_name ($instance)'")
  fi
  if ((${#requested[@]} == 0)); then
    printf 'NOTICE: web administration is reachable by every client that can reach the IPP port; set PRINTER_APP_SERVER_OPTIONS=no-web-interface to disable it\n' >&2
  fi
}

printer_app_state_error() {
  printf 'Persistent state is not writable or cannot be secured: %s; mount a writable volume with permissions for UID:GID %s:%s\n' "$1" "$(id -u)" "$(id -g)" >&2
  exit 73
}

# $1: state root; $2: application basename; remaining args: extra driver dirs.
printer_app_prepare_state() {
  local state="$1" app="$2" directory probe file
  shift 2
  umask 077
  local -a directories=("$state" "$state/ppd" "$state/spool" "$state/usb"
    "$state/cups" "$state/cups/ssl" "$state/.cups" "$state/.cups/ssl" "$@")
  for directory in "${directories[@]}"; do
    mkdir -p -- "$directory" || printer_app_state_error "$directory"
    # mkdir/-w alone do not catch a read-only or full filesystem.
    probe="$(mktemp "$directory/.write-check.XXXXXXXXXX")" || printer_app_state_error "$directory"
    rm -- "$probe" || printer_app_state_error "$directory"
    chmod 0700 -- "$directory" || printer_app_state_error "$directory"
  done
  for file in "$state/$app.state" "$state/$app.log"; do
    if [[ -e "$file" || -L "$file" ]]; then
      [[ -f "$file" && -w "$file" ]] || printer_app_state_error "$file"
    fi
  done
  chmod -R u+rwX,go-rwx -- "$state/cups/ssl" "$state/.cups/ssl" "$state/spool" \
    || printer_app_state_error "$state"
}

# Optional source paths support host tests. Preserve existing local edits,
# including dangling symlinks (never overwrite a volume's configured target).
printer_app_seed_cups() {
  local state="$1" snmp="${2:-/etc/cups/snmp.conf}"
  local quirks="${3:-/usr/share/cups/usb/org.cups.usb-quirks}" target
  target="$state/cups/snmp.conf"
  if [[ ! -e "$target" && ! -L "$target" && -e "$snmp" ]]; then
    cp -- "$snmp" "$target" || printer_app_state_error "$target"
  fi
  target="$state/usb/org.cups.usb-quirks"
  if [[ ! -e "$target" && ! -L "$target" ]]; then
    cp -- "$quirks" "$target" || printer_app_state_error "$target"
  fi
}

# $1: runtime directory (normally /run); remaining args: application command.
# Call last: owns the entrypoint's traps and exits with the first child's status.
printer_app_supervise() {
  local run="$1" attempt status
  shift
  # EXIT on errexit can run after function-local variables have gone out of scope.
  printer_app_children=()
  printer_app_stop_children() {
    local index pid
    for ((index=${#printer_app_children[@]}-1; index>=0; index--)); do
      pid="${printer_app_children[index]}"
      kill -TERM "$pid" 2>/dev/null || true
    done
    wait "${printer_app_children[@]}" 2>/dev/null || true
  }
  # shellcheck disable=SC2317 # Invoked by the signal traps below.
  printer_app_handle_signal() {
    trap - TERM INT EXIT
    printer_app_stop_children
    exit 143
  }
  trap printer_app_handle_signal TERM INT
  trap printer_app_stop_children EXIT
  mkdir -p -- "$run/dbus" "$run/avahi-daemon"
  dbus-daemon --system --nofork --nopidfile &
  printer_app_children+=("$!")
  for ((attempt=0; attempt<30; attempt++)); do
    [[ -S "$run/dbus/system_bus_socket" ]] && break
    sleep 0.1
  done
  [[ -S "$run/dbus/system_bus_socket" ]] || exit 1
  avahi-daemon --no-drop-root --no-chroot &
  printer_app_children+=("$!")
  for ((attempt=0; attempt<30; attempt++)); do
    [[ -f "$run/avahi-daemon/pid" ]] && break
    sleep 0.1
  done
  [[ -f "$run/avahi-daemon/pid" ]] || exit 1
  "$@" &
  printer_app_children+=("$!")
  # Even a clean early exit means the appliance is no longer serving.
  if wait -n "${printer_app_children[@]}"; then status=1; else status=$?; fi
  printer_app_stop_children
  trap - TERM INT EXIT
  exit "$status"
}

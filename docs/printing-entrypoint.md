# Shared printer startup library

The four printer applications share startup rules through
`/usr/libexec/printer-app/entrypoint-common.sh`. The library is installed by
`printing/entrypoint-common.bst` in `printing/runtime-stack.bst`, not the
devel-only `printing/base.bst`. Consumers not yet using the runtime stack must
add that element to their own stack. Adoption in each app repository is a
separate change after the library ships.

## Consumer example

Keep app-specific driver seeding, environment paths (including PPD paths), and
`SYSTEM_NAME` locally. Source the library from bash with `set -euo pipefail`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source /usr/libexec/printer-app/entrypoint-common.sh
app=ps-printer-app
state=/var/lib/ps-printer-app
printer_app_validate 'PostScript Printer Application' # optional port floor: 1024
printer_app_prepare_state "$state" "$app" # extra absolute driver dirs follow
printer_app_seed_cups "$state"
# Set app-specific BACKEND_DIR, FILTER_DIR, CUPS_SERVERBIN, CUPS_SERVERROOT,
# HOME, PPD_PATHS, STATE_FILE, SPOOL_DIR, USB_QUIRK_DIR, etc.; seed drivers here.
# Create /run/<app> if required. Retain the app's existing init/catatonit setup.
args=(-o "log-file=$state/$app.log" "${printer_app_args[@]}")
printer_app_start_countme "$state" "$app"
printer_app_supervise /run "$app" "${args[@]}" server
```

Sourcing the library does not touch state, change the umask, or install traps.

## Validation and arguments

`printer_app_validate SYSTEM_NAME [PORT_FLOOR]` runs before state changes.
It resets `printer_app_args` on every call. An unset/empty `PORT` adds no
override; explicit ports are decimal-normalised and bounded to 1–65535
(or the app's floor). Leading-zero padding is accepted without octal arithmetic
or integer overflow. Only `no-web-interface` is allowed as a server option.
Authentication service names and admin group names are syntax-checked first;
authentication is then refused because this PAPPL build has no PAM support.
A group cannot be enforced without authentication, so group-only settings also
fail closed. Syntax errors exit 64; unsupported authentication/group settings
exit 78. There is no host-dependent group lookup while PAM is disabled.

`PRINTER_APP_INSTANCE` is ASCII-normalised, trimmed and capped at 24 characters;
an empty result exits 64. Unset leaves the built-in system name unchanged.
The caller supplies its built-in `SYSTEM_NAME`, which prefixes the instance ID.
When web administration remains open, validation prints a notice on stderr.

## Persistent state and packaged defaults

`printer_app_prepare_state STATE APP [DRIVER_DIR...]` sets `umask 077`, probes
every mutable directory with a temporary file, checks existing state/log files,
and repairs directory modes to 0700 on every start. STATE itself is reset to
0700 only when the app's user owns it, so an operator-owned volume root is left
as mounted. TLS and spool contents also lose group/other access recursively.
Any managed directory, STATE included, or any parent of one below STATE that
is a symlink is refused before
anything is created, probed or chmodded, so nothing outside the volume changes.
Failures exit 73, including symlinks, read-only/full volumes or a failed
permission repair. Driver directories must be app-owned
absolute paths under STATE, not user-supplied arbitrary paths.

`printer_app_seed_cups STATE [SNMP_SOURCE [USB_QUIRKS_SOURCE]]` seeds missing
defaults without replacing existing files or symlinks; an absent packaged SNMP
default is tolerated, but a missing USB quirks database fails closed. The optional
source paths support host tests; production consumers use the packaged defaults.

## Daily active installation reporting

Call `printer_app_start_countme STATE APP` after preparing persistent state and
immediately before supervision. It launches `/usr/libexec/printer-app/countme.py`
as a noncritical direct Python child and stores `printer_app_countme_pid`.
`printer_app_stop_countme` terminates and reaps it; repeated stops are safe.
The supervisor calls stop on every cleanup path, but never starts reporting
automatically and never includes it in the fatal `wait -n` child list.
`printing/entrypoint-common.bst` supplies Python and CA certificates even for an
otherwise Python-free consumer such as Gutenprint.

The metric is **active reporting app installations per UTC calendar day**, not
unique hosts, physical printers, or print jobs. APP must be exactly
`ghostscript-printer-app`, `hplip-printer-app`, `gutenprint-printer-app`, or
`ps-printer-app`. The only payload is `{"image":"<app>/main:unknown"}`, sent by
HTTPS PUT to `https://countme.projectbluefin.io/v1/ping` with a 10-second network
timeout and normal certificate verification. Digest-based deployments cannot
reliably identify a release stream, so the stream remains `unknown`. No machine
IDs, IP addresses, tokens, or host paths are added to the payload.

The helper checks at startup and every four hours. STATE's private `.countme_day`
marker is atomically replaced only after HTTP 200 with JSON `success: true`.
The separate `.countme.lock` inode is retained and locked nonblocking, so
overlapping reporters on one volume cannot send simultaneously. Unsafe symlinks,
nonregular files, malformed markers, clock/read/write/lock and network failures
skip reporting without affecting printing. A backwards clock does not recount
an earlier day. State loss can recount; a lost acknowledgement cannot guarantee
exactly-once delivery. Keep `/var/lib/<app>` persisted (ChairLift binds
`~/printer-workspaces/<family>/<name>`) across disable/re-enable cycles.

Run the host-only behavioral regression with
`python3 -m unittest discover -s tests -p 'test_printing_runtime_layer_countme.py'`.
It intercepts stdlib HTTP transport and clocks and uses temporary state; never
validate by sending a valid production ping. Python API references consulted via
Context7 `/python/cpython`: `urllib.request`, `fcntl.flock`, and `os.replace`.

## Supervision

Call `printer_app_supervise RUN_DIR COMMAND [ARG...]` last, never in a shell
conditional that disables `errexit`. It owns TERM/INT/EXIT traps, waits for
D-Bus and Avahi readiness, then starts the app. The first child exit stops and
reaps all children in reverse order; zero becomes 1, other statuses are preserved,
and TERM/INT exit 143. Readiness failure exits 1 and cleans up. RUN_DIR is normally
`/run`; tests use a temporary directory with fake daemons.

## Host tests and maintenance

`tests/test_printing_runtime_layer_entrypoint.py` covers the union of consumer
validation cases plus state, seeding and supervisor behavior. Both
`just catalog-check` and the existing runtime-layer test discovery in CI run it.
Test fake tools belong in a separate directory from runtime state:
`avahi-daemon` is also the name of a runtime directory. Child PID storage must
outlive function locals: an EXIT trap triggered by `errexit` can run after the
supervisor function's local variables have gone out of scope.

The install element follows BuildStream's
[manual element tutorial](https://github.com/apache/buildstream/blob/master/doc/source/tutorial/running-commands.rst)
(local source plus `install-commands`) and
[install location contract](https://github.com/apache/buildstream/blob/master/doc/source/core_buildelement.rst#install-location)
(output under `%{install-root}`), consulted via Context7 `/apache/buildstream`.

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
and repairs directory modes to 0700 on every start. TLS and spool contents also
lose group/other access recursively. Failures exit 73, including read-only/full
volumes or a failed permission repair. Driver directories must be app-owned
absolute paths under STATE, not user-supplied arbitrary paths.

`printer_app_seed_cups STATE [SNMP_SOURCE [USB_QUIRKS_SOURCE]]` seeds missing
defaults without replacing existing files or symlinks; an absent packaged SNMP
default is tolerated, but a missing USB quirks database fails closed. The optional
source paths support host tests; production consumers use the packaged defaults.

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

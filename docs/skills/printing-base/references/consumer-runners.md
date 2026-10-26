# Consumer CI runners: keep BuildStream jobs on ubuntu-24.04

The printer-app repositories build with `just bst ...` on GitHub-hosted
runners. When Renovate bumped their `runs-on` from `ubuntu-24.04` to
`ubuntu-26.04` the builds broke (projectbluefin/fsdk-containers#332). The
failure is not a BuildStream, podman, or buildbox-fuse regression; it is a
host AppArmor policy leaking into the sandbox.

### Root cause

Ubuntu 26.04 runner images (apparmor 5.0.2, kernel 7.0) ship
`/etc/apparmor.d/gs`, an **enforcing** profile attached to `/usr/bin/gs`.
Ubuntu 24.04 (apparmor 4.0.1) has no such profile. AppArmor attaches a
profile on `exec` by path, and the `--privileged` podman container plus
`buildbox-run-bubblewrap`'s user namespace do not stop that: the FSDK
sandbox has its own `/usr/bin/gs`, the exec matches the host profile, and gs
runs confined. The profile only allows reads under `/usr/share/**`,
`/var/lib/ghostscript/**`, `/etc/paperspecs` and fonts, plus owner
read/write under `@{HOME}/**.<gs ext>`, `/tmp`, `/mnt/**` and `/media/*/**`.
The BuildStream build root is `/buildstream/<project>/<element>/` on a
buildbox-fuse mount, so every gs open there fails:

```
openat(AT_FDCWD, "testpage.ps", O_RDONLY)                        = -1 EACCES
openat(AT_FDCWD, "testpage.pdf", O_RDWR|O_CREAT|O_TRUNC, 0666)   = -1 EACCES
GPL Ghostscript: **** Could not open the file testpage.pdf .
```

Shell tools in the same sandbox (`cat`, `cp`, `touch`, `mkdir`) read and
write the same paths fine, and gs itself works when both its input and
output live under `/tmp`. Only elements that *execute* `gs` at build time
are affected (e.g. gutenprint's `printer-app/runtime-files.bst` rendering
`testpage.ps` to PDF). This repository's own `printing-base.yml` job passes
on ubuntu-26.04 because none of `printing/base.bst`'s elements run gs while
building; the runner label there is not a signal that consumers can move.

Evidence: gutenprint-printer-app run 36158590555 (26.04, only
`runtime-files.bst` fails) vs 36158593750 (24.04, same cache key `42f6a2c8`
passes); in-sandbox strace and `aa-status` probes on both images.

### What consumers must do

1. Pin every job that runs `just bst` (build, publish, verify) to
   `ubuntu-24.04`.
2. Stop Renovate from re-bumping it. The `github-runners` datasource is what
   proposes `ubuntu-26.04`; cap it in `renovate.json`:

   ```json
   {
     "packageRules": [
       {
         "description": "GitHub-hosted runners: stay on ubuntu-24.04 (26.04 ships an enforcing AppArmor gs profile that breaks gs inside the bst sandbox)",
         "matchDatasources": ["github-runners"],
         "matchPackageNames": ["ubuntu"],
         "allowedVersions": "<26"
       }
     ]
   }
   ```

   gutenprint-printer-app#52 and ps-printer-app#52 carry this rule.
3. Renovate does not alter `fsdk-containers` runner pins from the consumer
   side; this repository's `renovate.json` has no runner cap on purpose.
### If a job has to run on ubuntu-26.04

Unload the profile on the runner before the first `just bst`; it is host
policy, so nothing inside the element or `Justfile` can opt out of it:

```yaml
- name: Unload the AppArmor gs profile (Ubuntu 26.04 ships /etc/apparmor.d/gs)
  run: |
    if [ -f /etc/apparmor.d/gs ]; then
      sudo apparmor_parser -R /etc/apparmor.d/gs
    fi
```

Rewriting the element to copy its inputs to `/tmp`, run gs there and
install the result from `/tmp` also works, but ties the element to a
runner quirk; prefer the pin plus the Renovate cap.

The `rm: cannot remove '/buildstream/...': Read-only file system` line
quoted in #332 is BuildStream's post-command build-root cleanup on
successful 26.04 builds; the only 26.04 failure is the gs EACCES above.

Verified: on ubuntu-26.04 with the `gs` profile unloaded, the unmodified
`printer-app/runtime-files.bst` builds and caches (clubanderson fork run
36213750777); the same element fails on the same image with the profile
loaded.

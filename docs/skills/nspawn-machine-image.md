---
name: nspawn-machine-image
version: "1.4"
last_updated: 2026-10-16
id: nspawn-machine-image
one_line_purpose: Build a non-distroless systemd-nspawn machine image rootfs from FSDK.
entry_point: docs/skills/nspawn-machine-image.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [nspawn, machinectl, rootfs, brew]
description: "Use when building or consuming FSDK Brew nspawn machines: EROFS/tar output, genuine Git seeds, offline portable Ruby, and guest user scopes."
metadata:
  type: procedure
  context7-sources:
    - /apache/buildstream
    - /homebrew/brew
    - /systemd/systemd
---

# nspawn Machine Images (raw and tar)

## When to Use

Use for a **full Linux developer environment** booted by `systemd-nspawn`, not
an OCI distroless image. Reference: `elements/brew/*` and
`elements/oci/brew-nspawn.bst`.

## When NOT to Use

Normal OCI images still follow [`add-new-image.md`](add-new-image.md); this
exception does not expand that lane. Do not rebuild upstream-maintained OCI tools.

## Output and consumer contract

`oci/brew-nspawn.bst` exports three files:

- `homebrew-env-7.0.10.raw.zst`: a plain, single-filesystem **EROFS** machine,
  not a GPT disk, with the immutable prefix seed at
  `/usr/share/bluefin/homebrew-seed`. `/home/linuxbrew/.linuxbrew` is empty.
- `homebrew-env-7.0.10.tar.zst`: the existing complete rootfs, with its prefix
  directly at `/home/linuxbrew/.linuxbrew`, for `machinectl import-tar`.
- `SHA256SUMS`: covers both compressed outputs.

The raw consumer copies the seed once to a persistent, single-nonroot-owner
directory and binds it at `/home/linuxbrew/.linuxbrew`. Use `Volatile=overlay`
for writable `/etc` and `/var` (sysusers, machine-id, PAM/logind, user managers).
The underlying image remains immutable. Bind a persistent user home as well.
Never bind all host `/run` or host root; grant host-engine access only through
explicitly authorized sockets in the consumer. Producer ships no tmux/formulae.

Server consumes the raw through a BuildStream junction and wraps its release name;
the producer's version axis remains the pinned Brew release, not Server's version.
Host-specific UID/account mapping and container-engine authorization belong to the
consumer. The standalone producer recipes retain the original `linuxbrew` account
at UID/GID 1001 and `/home/linuxbrew` host bind. No guest user should own `/usr`.

## Core Process

1. `brew-deps.bst` reuses FSDK `components/*` plus `base/base-stack.bst`.
   Shell, compiler/headers, locales, git/openssh/curl/patchelf, init, D-Bus provider,
   logind, NSS and PAM are prerequisites, not a second distro package set.
2. `brew-runtime.bst` excludes only debug/doc/tests, keeping devel, locale,
   shells, sysconf, sysusers and user-service units. Never apply SLIM here.
3. `portable-ruby.bst` imports Homebrew's exact **portable Ruby 4.0.7_1** bottle
   for each architecture. The digests are copied from the pinned Brew
   `Library/Homebrew/vendor/portable-ruby-{x86_64,arm64}-linux` files; FSDK's
   unrelated system Ruby cannot replace them.
4. `brew-prefix.bst` stages the pinned `git_repo` checkout and runs
   `files/prepare-seed.sh` offline. It preserves upstream objects, tag and HEAD;
   adds the actual origin/fetch refspec, `main` tracking branch and portable
   Ruby `current` symlink; creates an empty Cellar. No installer/fetch is run.
5. `oci/brew-nspawn.bst` finalizes init, users, machine-id, locale, NSS/PAM and
   system/user bus enablement. It moves the seed into the canonical prefix for
   tar export, then back into `/usr/share` for raw packing. No duplicate prefix.
   `mkfs.erofs` uses fixed UUID/time and root ownership; zstd is single-threaded.

### Why the local `ghcr_tar` source exists

Public GHCR bottle requests return HTTP 401 without authentication. The source
plugin obtains an **anonymous**, repository-scoped pull token during *source
fetch*, follows storage redirects without forwarding registry credentials across
hosts, verifies SHA256, and safely stages the archive. Tokens are not stored in
sources/artifacts. Both actual 4.0.7_1 blobs are available from GHCR; there is no
matching release in the older `Homebrew/homebrew-portable-ruby` GitHub releases.
Do not put `curl`/`brew vendor-install` network commands in build/install commands.

When changing Brew's source pin, update the portable-Ruby version and both bottle
digests **from that same commit**. Preserve architecture parity; never pick a
floating interpreter or a convenient older GitHub release. The transport is
restricted to Homebrew's portable-ruby repository and needs Python >=3.12 in bst2.

On a Brew source-pin conflict, retain the new release's `track`/`ref`, the seed
source `directory` and local assembly source, and align both output-version
variables. Read all three vendor files at that exact upstream commit before
changing the bottle pins: 7.0.10 moved from 4.0.7 to 4.0.7_1 with two new digests.
Neither green seed unit tests nor an older release's boot run validates the new
producer; dispatch native artifact/boot verification on the resolved branch.

### Offline boot versus normal package management

Brew 7.0.10 fetches its package API before Ruby commands such as `brew config`.
The producer bundles the matching Ruby interpreter, not a package API snapshot.
Verify Ruby and the shell-level `brew --prefix` without network; exercise normal
`brew config`, installs and updates on a networked consumer. Preserve upstream API
behavior; do not add a mirror, cache-initialization service, or API-disable default.

### Git export: inspect before patching

`buildstream-plugins-community` **2.3.1** `git_repo` already preserves `.git`:
`GitMirror.stage()` calls `stage_repository()` with real commit/tree/tag objects
and shallow boundaries. It omits origin and detaches HEAD. Therefore the seed
only needs offline refs/config changes; **no plugin patch, git init or invented
initial commit**. `brew update` then fetches the genuine upstream repository.

## Consumer recipes

```sh
just brew-check             # source/seed behavioral regression tests, no build
just build-brew             # build this lane only
just export-brew            # both formats + checksums in dist/
just verify-brew            # inspect actual tar and raw roots
just verify-brew-boot        # systemd host/root: boot raw without external network
just install-brew           # raw default; imports machine named homebrew
just install-brew tar       # existing tar format remains supported
just run-brew config         # argument/exit-code preserving systemd-run bridge
just uninstall-brew         # preserves the writable host prefix
```

Inspection needs Python >=3.12, git, zstd, `fsck.erofs`, and `readelf` (binutils).
Installation requires a systemd host, root privileges and an EROFS-enabled kernel.
`install-brew` populates a pristine prefix before mounting the host home, refuses
to overwrite a nonempty uninitialized prefix, and preserves existing upgrades.
It does not make arbitrary host users owners; Server supplies its own owner model.
`run-brew` preserves argv without shell interpolation and disables systemd's
environment expansion. Do not replace it with `machinectl shell`: that command
does **not** propagate the command's exit status.

## Verification

`verify-brew.py` validates checksums for exactly both outputs, resolves guest
symlinks within the guest root, checks real Git release identity/origin/refspec,
portable Ruby matching `current`, empty Cellar, init, system/user D-Bus, NSS/PAM
and recursive ELF interpreter/library closure. It reads UAPI.12 FDO dlopen notes
from shipped systemd helpers as well as `DT_NEEDED`: only `priority: required`
is mandatory; a `soname` list gives ordered alternatives, not cumulative deps.
FSDK's systemd runtime omits `tpm2-tss.bst`, although `systemd-tpm2-setup` declares
ESYS/RC/MU/device-TCTI required. Keep the existing FSDK component in `brew-deps`;
do not maintain a second hardcoded SONAME contract. Path-only listings are not
enough. `tests/brew-boot.sh` boots raw without external network, runs the bundled
Ruby and shell-level prefix command nonroot, checks logind/user@1001, exercises
guest user services including exit 37, and verifies UID 1001 prefix writes.
It requires root; `machinectl shell` is not an assertion transport.

`.github/workflows/brew-nspawn.yml` runs source/seed behavioral tests and native
`just verify-brew` artifact inspection for relevant PRs. Full native
x86_64/aarch64 artifact+offline boot checks run weekly/on demand. Keep these
separate: adding a boot-only job must not remove the existing PR artifact gate.
Nothing publishes these machine files through the OCI image matrix.

`build-brew` uses the same bounded GNOME junction source-fetch retry as the OCI
build recipe. Only fetching is retried; the actual producer build runs once,
so deterministic build failures are not hidden behind repeated builds.

The PR paths filter covers brew sources and shared build inputs: the base stack,
FSDK and GNOME/plugin junctions, `include/**`, `patches/**`, `project.conf`,
Justfile, and the workflow itself. Include the authenticated source plugin,
verification script, source/seed tests and boot script too. Directory patterns
must use `/**`; unrelated OCI-only edits should skip this heavy build. Smoke-test
matching and non-matching paths against the actual filter rather than pinning
its wiring in permanent tests. GitHub's [workflow syntax](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#onpull_requestpull_request_targetpathspaths-ignore)
documents PR path filtering. The Homebrew release pin is `brew-prefix.bst`'s
`track:`; the Justfile's `brew_version` is read from it, and
`tests/test_brew_version_pin.py` fails if `brew-nspawn.bst`'s `brew-version`
(which names the artifacts) differs.

Before handing off a verified producer, require:

- [ ] `just brew-check` and `just validate` pass.
- [ ] `just verify-brew` validates both complete formats.
- [ ] `just verify-brew-boot` passes natively for x86_64 and aarch64.
- [ ] Skill catalog and workflow inventory checks are current.

## Architecture Risks

- **Both architectures require their matching portable bottle**; Homebrew calls
  aarch64 `arm64_linux`. This is distinct from the x86_64 baseline; never enable
  x86_64_v3. Subsequent formula bottle coverage is upstream's responsibility.
- **EROFS + overlayfs are host-kernel requirements**, not guest-only components.
  Raw images are single filesystems, so importing does not provide dm-verity;
  consumers must enforce their signed release/checksum trust separately.
- **PrivateUsers=no is not a strong hostile-code boundary**. The standalone
  producer recipe is for an explicitly trusted single-owner environment. Host
  engine socket access confers that engine's privilege level; it is not made
  safer by a terminal multiplexer or a filesystem bind.
- **User scopes depend on the host/guest systemd bridge**, logind, a guest user
  manager, NSS, PAM, user bus and correct UID mapping. Test the actual consumer
  security settings; do not infer readiness from PID1 alone.

## Sandbox gotchas

- `base-stack` has coreutils/bash but not grep. Generate passwd/group/config with
  `printf`, not `grep || echo`; do not use YAML-indented literal heredocs.
- Always unlink staged files before rewriting. BuildBarn stages hardlinks from
  its pool; truncating them can corrupt unrelated artifacts with the same digest.
- BuildStream's user namespace cannot chown files to UID 1001 (`EINVAL`). The
  consumer sets ownership of the writable prefix/home, not the image producer.
- Merged `/bin`, `/sbin`, `/lib` are symlinks; validate the resolved guest paths.
  `/sbin/init` must point to `/usr/lib/systemd/systemd`, not just exist.
- Empty `/etc/machine-id` allows per-machine initialization. Preserve sysusers
  and tmpfiles content, and a writable runtime layer for their first-boot work.
- Tar shells out to zstd. Both tar/zstd and erofs-utils belong in assembly
  build-depends, not just the guest runtime.

## Common Rationalizations

| Temptation | Required correction |
| --- | --- |
| FSDK Ruby exists, so no portable bottle is needed | Match the pinned Brew vendor Ruby and both architecture digests. |
| A source archive is enough; invent Git history | Retain upstream objects/tag/commit, and add only refs and origin. |
| File names prove the machine works | Verify resolved paths, ELF closure and offline guest user scopes. |

## Red Flags

- Network installers or interpreter downloads inside build/install commands.
- Fake initial Git commits, missing origin, or detached updatable seed branches.
- Raw prefix duplication, root-owned runtime prefix, or preinstalled formulae.
- Host-root/all-host-run binds or broad privileged bridge permissions.
- `machinectl shell` used where exit-code fidelity is required.

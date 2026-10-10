# Verify Distroless — Extending Coverage

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

## Adding test coverage

### When adding a new runtime component or image

Follow the three-element pattern in [`add-new-image.md`](../../add-new-image.md), then
extend coverage:

1. **Confirm upstream coverage.** Check that the component exists and is built/tested
   upstream:
   ```
   just bst show freedesktop-sdk.bst:components/<name>.bst
   ```
2. **Add a binary smoke test.** In the `verify` recipe, add a branch that executes
   the primary binary directly (e.g.
   `podman run --rm "$REF" nginx -v >/dev/null`). Distroless images have no shell,
   and `ldd` inside BuildStream's sandbox does not replicate the stripped container
   rootfs — execution is the only way to prove all dynamic dependencies survived
   `compose`. (Today the local smoke branches cover skopeo, python, buildah,
   qemu-img, and lab-runner; `base`/`static` only get their `/usr/bin/true`
   smoke in the post-publish `publish-smoke` job — add a local branch when the
   image gains a real binary.)
3. **Record the image size.** Measure uncompressed Podman size on both
   architectures and include it in the PR so future growth can be reviewed.
4. **SBOM registration is automatic.** `just sbom <name>`/`just sboms` resolve the
   variant from `elements/targets.json` — nothing to hand-register.
5. **Document runtime-specific pruning.** If the new image needs extra `rm` steps
   beyond the shared SLIM recipe (e.g. Python stdlib tests), document *why* each
   removal is safe and add a matching `grep` negative assertion to `verify` so
   the gate fails if the bloat creeps back.
6. **Run the full local pipeline.**
   ```
   just validate && just build && just verify && just sbom <name>
   ```

### When adding a new FSDK series (e.g. `26.08`)

A new upstream minor line can rename components, restructure runtime stacks, or
change default package contents. Treat it as a coverage refresh:

1. **Update the junction.** Pin `elements/freedesktop-sdk.bst` to the new ref and
   run `just validate` to confirm the graph resolves and patches apply cleanly.
2. **Reconcile stack dependencies.** Review upstream release notes and `bst show`
   output for renames such as `public-stacks/runtime-minimal.bst` vs
   the FSDK stack that carries their shell tooling.
3. **Record size changes.** Measure both architectures and call out significant
   growth in the PR body.
4. **Re-run all smoke tests.** Execute every image's primary binary on `x86_64` and
   `aarch64`; a library that moved domains can pass `bst show` but still fail at
   runtime.
5. **Check tags and labels.** Run `just tags` and inspect the exported image labels
   (`io.projectbluefin.fsdk.version`, `io.projectbluefin.fsdk.ref`) to confirm they
   describe the new series correctly.
6. **Validate SBOM tooling.** If `buildstream-sbom` needs a newer pin for the new
   FSDK schema, update the pinned commit in the `sbom` recipe and the pip cache key
   in `.github/workflows/oci-images.yml`.
7. **Watch upstream reports.** The upstream CVE, reproducibility, and SBOM reports
   for the new series are inherited automatically, but verify they are being
   published on the upstream branch before relying on them for a production tag.

## Adding a gate

When you cut something in the SLIM recipe that must stay gone, add a matching
negative assertion so the build fails if it creeps back. Gates are no longer
hand-written in the `verify` recipe — the recipe reads its contract from each
image's catalog record, so declare the new check there instead of editing the
recipe:

- A path or binary that this image must contain goes in
  `gates.require_paths:` / `gates.require_binaries:` in
  `catalog/<image>.yaml`.
- A piece of bloat that must never reappear across every slim image goes in the
  shared `FORBIDDEN` patterns in `scripts/verify_contract.py` — that is where the
  slim-bloat gate already lives. The recipe applies those automatically, so there
  are no `[N/M]` labels to number.

### When slim.extra removes a per-image CLI (issue #421)

The shared SLIM recipe's `no-shell`, `no-sanitizers`, `no-locale-archive`, and
`no-debug-symbols` gates cover the OS layer. When a record's `slim.extra`
removes a CLI pulled in by the runtime closure that the shared recipe cannot
cover, declare the path in the record's `gates` block so the merge gate
asserts the file is gone:

```yaml
gates:
  forbid_paths:
    - usr/share/misc/magic.mgc       # libmagic's database; buildah does not call file(1)
    - usr/libexec/podman/aardvark-dns # netavark's DNS server; only runs on bridge networks
  forbid_binaries:
    - dmesg                          # util-linux; buildah never reads the kernel ring buffer
```

`forbid_paths` matches the rootfs path verbatim (`grep -qxF`); `forbid_binaries`
projects the listing with `awk -F/ '{print $NF}'` and matches each basename
with `grep -qxF`, so a basename is taken as a fixed string (regex
metacharacters are literal) and cannot accidentally match a longer sibling
(`find` does not match `find-something`). Use `forbid_paths` when the absolute
path is part of the contract; use `forbid_binaries` when only the basename
matters and the binary could land in `usr/bin` or `usr/sbin`. The lists
empty by default, so an image with no `slim.extra` is unaffected.

Forbidding a **directory** with `forbid_paths` requires the trailing slash —
`tar -tf` lists directories as `usr/share/foo/` while a file at that path is
listed without the slash, so an entry without the slash never matches the
directory and the gate silently passes. Use `usr/share/foo/` to forbid the
directory and a separate file entry for individual files inside it.

If the removed file is matched by a directory glob (e.g. an entire `usr/bin/*/`
sibling tree), prefer widening the shared SLIM recipe's regex in
`include/slim.yml` so the gate covers every image. `forbid_paths` is for
per-image paths the shared recipe should not adopt.

Run `just verify` to confirm the new gate both fires and passes.

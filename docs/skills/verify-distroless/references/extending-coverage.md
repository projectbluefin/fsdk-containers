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
2. **Declare the smoke test in the catalog.** The `verify` recipe no longer
   carries per-image smoke branches — it derives both the podman options and the
   command arguments from each record's `smoke:` block
   (`scripts/verify_contract.py:smoke_argv`; the recipe reads
   them at `Justfile:359`). For the common case where the image's entrypoint
   already is the binary you want to exercise, set `args` to the arguments you
   want appended:
   ```yaml
   smoke:
     args: ["--version"]
   ```
   `catalog/buildah.yaml`, `catalog/qemu-img.yaml`, `catalog/python.yaml`, and
   `catalog/review-runtime.yaml` all use this form. An image with no declared
   entrypoint puts the binary first instead — `catalog/skopeo.yaml` uses
   `args: ["skopeo", "--version"]`.
   If the primary binary is not the entrypoint, override it so `podman run`
   reaches the binary the same way a user would:
   ```yaml
   smoke:
     entrypoint_override: ["/usr/bin/argo"]
     args: ["version", "--short"]
   ```
   `catalog/lab-runner.yaml` is the only record that needs this — bash is its
   declared entrypoint, but `argo` is what the smoke test actually exercises.
   For an image that ships no executable surface worth smoke-testing (today:
   `base`, `static`, declared as `smoke: none`), the recipe falls back to the
   plain runnability probe; `publish-smoke`'s post-publish `/usr/bin/true` probe
   covers those. Distroless images have no shell, and `ldd` inside BuildStream's
   sandbox does not replicate the stripped container rootfs — execution is the
   only way to prove all dynamic dependencies survived `compose`, so every
   non-`none` image carries one (and the python probe deliberately goes past
   `--version` to exercise stdlib — see the comment in `catalog/python.yaml`).
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

Run `just verify` to confirm the new gate both fires and passes.

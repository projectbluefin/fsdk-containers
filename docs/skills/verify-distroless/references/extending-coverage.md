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
3. **Set a size ceiling.** Add a `MAX_BYTES` case in the `verify` recipe for the new
   image. Calibrate it against uncompressed Podman sizes on **both** architectures
   and leave headroom for normal FSDK point-release growth.
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
3. **Recalibrate size ceilings.** FSDK minor lines usually grow. Do not encode the
   exact current size; set ceilings with realistic headroom for the new series and
   both architectures.
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
`grep` assertion to gate `[5/N]` in the `verify` recipe so the build fails if it
creeps back. Renumber the gate labels. Keep the image size ceilings in the
`verify` recipe calibrated against both architecture builds; allow headroom for
normal FSDK point-release growth rather than encoding today's exact size.

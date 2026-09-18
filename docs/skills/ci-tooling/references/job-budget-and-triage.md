# CI Tooling — Job Budget and Failure Triage

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

## The CI job budget — 60 concurrent jobs, org-wide

**The constraint is concurrency, not the 256-job matrix limit.** This trips people up because
the matrix limit is the documented number everyone quotes.

| Limit | Value | Raisable? |
|---|---|---|
| Job matrix | 256 jobs / workflow run | No |
| **Concurrent jobs, Team plan** | **60, shared across the whole org** | Yes, support ticket |
| Job execution time (GH-hosted) | 6 hours | No |
| Unique reusable workflows / top-level file | 50 (nesting 10 deep) | — |

`projectbluefin` is on the **Team** plan, so all 60 concurrent job slots are shared by every
repository in the org — not 60 per repo, and not 60 per workflow.

**Each OCI image costs 5 jobs**: `build` x2 arch, `manifest` x1, `publish-smoke` x2 arch. With
~5 jobs of non-OCI overhead per run (`matrix`, `summary`, `vm-guest`), a full catalog run
saturates the org at roughly **11 images**:

```
(60 - 5 overhead) / 5 jobs per image = 11 images
```

Failure here does not look like a failure. Jobs **queue** rather than error, so the symptom is
every other repo in the org waiting behind a catalog build, with nothing pointing at the cause.
Watch the job count, not just the red X.

Build time is not the constraint and has never been: the entire 7-image catalog builds serially
in ~40 minutes on `x86_64` (~29 on `aarch64`) against a 180-minute job timeout. Fan-out is
mostly scheduling overhead.

Today the `matrix` job resolves `oci_images` from `elements/targets.json` and
the build fans out **one reusable call per image** — adding image N+1 changes
no workflow file. The agreed remedy (#127) if the budget binds is **sharding**:
matrix entries become batches of ~10 images, giving `jobs = 5 x ceil(N / 10)`.
Re-derive the batch size when any single image's build exceeds ~18 minutes.

When batching a loop over images, **do not `set -e` out of the loop.** Collect per-image
results, print one line per image, and exit non-zero at the end — otherwise one bad image hides
the other nine behind a single click.

## Debugging a failed job — check for artifacts before concluding "no logs"

`gh run view --log` / `--log-failed` show only what a step printed to stdout. Anything a job
uploads with `actions/upload-artifact` — captured serial consoles, core dumps, test output — is
**not in the logs** and must be downloaded separately:

```console
$ gh run view <run-id> --json jobs --jq '.jobs[] | select(.conclusion=="failure") | .name'
$ gh run download <run-id> -n <artifact-name>
```

This is not hypothetical. #110 (`podman-vm` guest fails its boot test under FSDK 26.08) sat
undiagnosed for ~12 hours with `main` red, recorded as *"CI logs for this job could not be
retrieved [...] without the captured serial console there was nothing to diagnose from"* — while
`vm-guest.yml` had been uploading `vm-boot-serial-<arch>` on every single failure. The whole
diagnosis was one `gh run download` away.

**Before writing "cannot reproduce" or "no logs available", list the run's artifacts.** If a job
captures diagnostic state on failure, say so in the failure message itself so the next person
does not have to know the artifact exists:

```console
FAIL: guest did not reach its ready point within 300s
      (serial console uploaded as artifact 'vm-boot-serial-x86_64')
```

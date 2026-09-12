Publishable artifacts and owning pipelines

Summary

This document identifies which repository pipelines own the publication of VM "runner" OCI images and the VM guest (podman-vm) disk artifacts, the naming / tag / release conventions consumers should verify, and the available signatures / attestations they can use to validate authenticity and integrity.

Owning pipelines

- OCI images (lab-runner, qemu-img, and other oci/* images): .github/workflows/oci-images.yml (invoked by .github/workflows/build.yml)
  - What it publishes: per-arch images pushed to GHCR as ghcr.io/projectbluefin/<image>-<arch>:<point-tag> and then assembled into a multi-arch index at ghcr.io/projectbluefin/<image>:<point-tag> (point-release tags come from `just tags`).
  - Signatures & provenance: the manifest list digest is keyless-signed with Cosign in the manifest step (cosign sign -y "${REPO}@${DIGEST}"); the SBOM ("${IMAGE}.spdx.json") is attached as an ORAS referrer and the SBOM referrer is also keyless-signed. A GitHub artifact attestation is produced and pushed to the registry via actions/attest.
  - Consumer verification: verify the canonical index digest/tag and its Cosign signature with keyless verification: `cosign verify --keyless ghcr.io/projectbluefin/<image>@sha256:<manifest-digest>`; confirm SBOM referrer with ORAS or consult the registry. Prefer verifying the manifest digest rather than mutable tags like :latest.

- VM guest disk assets (podman-vm / donate-clanker VM disk): .github/workflows/vm-guest.yml (invoked by .github/workflows/build.yml)
  - What it publishes: per-architecture compressed disk artifacts and checksums uploaded as GitHub release assets under a point-release tag v${{fsdk_version}} (the `just publish-podman-vm` recipe performs the release creation and per-arch upload). Filenames follow the pattern: donate-clanker-vm-<fsdk-version>-<arch>.(raw|qcow2).zst and their .sha256 checksums, plus podman-vm-<arch>.spdx.json SBOM.
  - Signatures & provenance: the workflow produces GitHub artifact attestations (actions/attest) and attaches SBOM attestations; the various artifacts are uploaded to a GitHub release where consumers can fetch by tag and name. There is no per-asset Cosign manifest signature step in the current publish script; instead, attestations and the release immutability model are used to provide provenance and immutability guarantees.
  - Consumer verification: consumers should pin to the exact release tag (v<fsdk-version>) and the specific asset filename, verify the asset's SHA256 checksum (provided as separate release assets), and prefer verifying the workflow-generated attestations where practical. Example expected asset name: `donate-clanker-vm-25.08.15-aarch64.raw.zst` and `donate-clanker-vm-25.08.15-aarch64.raw.zst.sha256`.

Artifact contract (what downstream review should verify)

Downstream consumers (e.g. projectbluefin/review) should verify the following as part of a reproducible, immutable consumption policy:

- For OCI-based runners (lab-runner, qemu-img, etc):
  - Pin to the manifest digest: ghcr.io/projectbluefin/<image>@sha256:<manifest-digest>
  - Verify the manifest list signature with Cosign (keyless): `cosign verify --keyless ghcr.io/projectbluefin/<image>@sha256:<manifest-digest>`
  - If SBOM is required: fetch the attached SPDX SBOM referrer (attached in the oci-images workflow) and verify its Cosign signature.

- For VM guest disk artifacts (podman-vm):
  - Pin to the GitHub release tag and exact asset filename: `https://github.com/projectbluefin/fsdk-containers/releases/download/v<fsdk-version>/donate-clanker-vm-<fsdk-version>-<arch>.raw.zst`
  - Download and verify the provided .sha256 checksum file included as a release asset (the `just publish-podman-vm` recipe uploads the uncompressed disk checksum and the compressed checksum alongside the disk).
  - Where possible, verify the GitHub artifact attestation (actions/attest) associated with the release assets.

Notes and recommendations

- Prefer digest-based pinning for OCI images (ghcr.io/...@sha256:...) rather than mutable tags. The oci-images workflow already signs the manifest list digest with Cosign keyless signatures.

- The podman-vm publication is intentionally per-architecture and uses GitHub Releases due to large asset sizes. The Justfile `publish-podman-vm` recipe enforces preflight size limits, rollback on failure, and post-verify checks. Consumers must rely on the provided .sha256 checksums and the release immutability model.

- If explicit Cosign referrers for the release assets are required (Cosign provenance referrers pointing at the uploaded release assets), an enhancement would be to publish a signed referrer (via cosign attach or `cosign sign-blob` with a payload referencing the release asset URL/digest) after upload. This repo currently signs OCI manifest lists and SBOM referrers; adding per-release-asset Cosign referrers would be a follow-up change.

Map to repository pipeline files

- .github/workflows/oci-images.yml: builds per-arch images, assembles manifest index, cosign-signs manifest list, attaches SBOM via ORAS, and creates artifact attestations.
- .github/workflows/vm-guest.yml: builds per-arch podman-vm guest disk, boot-tests, generates SBOM, compresses disk, and uses `just publish-podman-vm` (Justfile) to upload release assets and attach attestations.
- Justfile: `publish-podman-vm` implements the atomic per-architecture release upload logic and verification rules.

If maintainers want explicit Cosign referrers on GitHub release assets, I can follow up with a patch to publish per-asset keyless Cosign signatures/provenance referrers after `just publish-podman-vm` completes.

— hive: backend=goose model=gpt-5-mini

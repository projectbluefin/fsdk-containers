# Security Policy

## Supported images

Only images published to `ghcr.io/projectbluefin/*` from the `main` branch of
this repository are supported. The `:latest` and minor-line tags (e.g.
`:25.08`) receive rebuilds as freedesktop-sdk ships CVE fixes; point-release
tags (e.g. `:25.08.13`) are immutable snapshots and are **not** patched —
consumers pinning point releases should track the minor line for security
updates.

## Reporting a vulnerability

Please report vulnerabilities privately via
[GitHub private vulnerability reporting](https://github.com/projectbluefin/fsdk-containers/security/advisories/new).
Do not open public issues for security reports.

For vulnerabilities in the underlying packages (glibc, Python, etc.), report
upstream to [freedesktop-sdk](https://gitlab.com/freedesktop-sdk/freedesktop-sdk)
— these images inherit their CVE patching from FSDK and pick up fixes on the
next FSDK point release.

## Verification

All published images are keyless-signed with cosign and carry an attached SPDX
SBOM — see the "Verify signatures" section of the README.

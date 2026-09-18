# Slim an Image — Prebuilt Static Binaries

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

Do not assume every upstream Go binary is already stripped, or that changing
versions will make it smaller. Inspect and measure each release artifact with
`file` and `stat`, then smoke-test the stripped copy before changing its element.
Measured on Argo v4.0.8 (current pin: v4.1.1): the release contains debug data,
and GNU `strip --strip-unneeded` reduced the amd64 CLI from 190,044,513 to
142,699,000 bytes while preserving its command surface. Argo v3.7.17 was nearly
the same size as v4 before and after stripping, so downgrading does not recover
space. kubectl v1.36.3 is already stripped and does not benefit from another pass.

Manual elements cannot rely on BuildStream's automatic stripping when
`freedesktop-sdk-stripper` is absent from the sandbox. Keep
`strip-binaries: ""`, add `freedesktop-sdk.bst:components/binutils.bst` as a
build dependency, and explicitly strip only artifacts whose measured size
decreases. Build dependencies do not enter the composed runtime image.

Keep a stripped CLI's execution check in `just verify`, using a local-only
subcommand. For `lab-runner`, invoke the binary directly with
`--entrypoint /usr/bin/argo` and `version --short`; the Argo CLI documents
`--short` as printing only its version. Check kubectl independently with
`kubectl version --client`, which avoids requiring a cluster. These checks
make a stripping regression fail the image contract rather than relying on a
one-time manual smoke test.

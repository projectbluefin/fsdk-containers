# fsdk-containers Skill Router

Agent entry point for `projectbluefin/fsdk-containers`. Find the skill that
matches your task, load only that skill, then act.

`fsdk-containers` brings distroless patterns to freedesktop-sdk (FSDK).

## Read order

1. [`AGENTS.md`](../AGENTS.md) — repo contract, build commands, hard rules.
2. This file — task→skill mapping.
3. The skill file named in the table below.
4. [`skills/index.md`](skills/index.md) — generated catalog of every skill.

## Fast paths

| If your task is... | Load |
| ------------------ | ---- |
| Add a new distroless image (python, node, etc.) | [`skills/add-new-image.md`](skills/add-new-image.md) |
| Add a component + stack only, no OCI image | [`skills/add-fsdk-component/SKILL.md`](skills/add-fsdk-component/SKILL.md) |
| Add a non-distroless nspawn machine image (dev env, tarball) | [`skills/nspawn-machine-image.md`](skills/nspawn-machine-image.md) |
| Add a bootable EFI/raw VM guest image (QEMU disk) | [`skills/vm-podman-guest/SKILL.md`](skills/vm-podman-guest/SKILL.md) |
| Make an image smaller / apply the SLIM recipe | [`skills/slim-an-image.md`](skills/slim-an-image.md) |
| Move to a new FSDK release / retag | [`skills/bump-fsdk-version.md`](skills/bump-fsdk-version.md) |
| Prove an image is still distroless | [`skills/verify-distroless.md`](skills/verify-distroless.md) |
| Supply chain security (signing and SBOM) | [`skills/signing-and-sbom.md`](skills/signing-and-sbom.md) |
| Add donate-clanker VM artifacts | [`skills/donate-clanker-vm-artifacts.md`](skills/donate-clanker-vm-artifacts.md) |
| Write or debug a CI workflow | [`skills/ci-tooling/SKILL.md`](skills/ci-tooling/SKILL.md) |
| Run local/agent builds on the ghost cluster (remote execution) | [`skills/remote-execution.md`](skills/remote-execution.md) |
| Set up custom builds and configure GHA/BuildStream caching | [`skills/custom-builds-and-caching.md`](skills/custom-builds-and-caching.md) |
| Automate ArtifactHub submissions | [`skills/artifacthub-automation.md`](skills/artifacthub-automation.md) |
| Verify the brew nspawn machine image | [`skills/nspawn-machine-image.md`](skills/nspawn-machine-image.md) |
| Container quality standards and SRE tagging | [`skills/container-standards.md`](skills/container-standards.md) |
| Run or respond to a security audit / review | [`skills/security-review.md`](skills/security-review.md) |
| Finishing a task (always) | [`skills/skill-improvement.md`](skills/skill-improvement.md) |

## What belongs in `docs/skills/`

Workflow knowledge and operational runbooks any agent needs to work in this repo.
**Not here:** agent-instruction files (`AGENTS.md`), which tools load separately,
and session or progress notes, which are banned outright — those live in the
agent's session folder.

## Standing facts

- BuildStream runs in the FSDK `bst2` container via `just bst`. Nothing to install
  but `podman` + `just`.
- Local/agent builds execute on the ghost cluster's BuildBarn grid by default
  (`just bst` injects remote-execution config); `BST_LOCAL=1` is the explicit
  opt-out. CI runners build locally per-arch.
- Compose from FSDK `components/*`, never `platform.bst`.
- Slim by default; keep tzdata + common charsets + CA certs.
- `just verify` is the merge contract: a per-image size ceiling, 5 distroless
  gates (3 for the shell-enabled `lab-runner`), and a smoke test.
- There is deliberately no `:latest` tag. The FSDK minor line is the most
  permissive tag published.
- `elements/targets.json` is the single canonical manifest for the OCI image
  build/manifest matrices — see
  [`skills/ci-tooling/SKILL.md`](skills/ci-tooling/SKILL.md).

## Catalog

`docs/skills/index.json` and `index.md` are generated from skill front matter by
`scripts/generate_skill_index.py`. After adding or editing a skill, run:

```bash
python3 scripts/generate_skill_index.py --write
```

and commit the regenerated files alongside your change. Front-matter fields are
validated against `docs/skills/index.schema.json`; see
[`common/docs/skills/write-a-skill.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/write-a-skill.md)
for the field reference and the 200-line soft / 500-line hard size limits.

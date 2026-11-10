kind: manual
description: Fetch the mikefarah/yq YAML/JSON/XML CLI processor for lab-runner

build-depends:
  # FSDK 26.08 removed the shell from runtime-minimal; these commands
  # are shell scripts, so declare the interpreter explicitly.
- freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  # A bare `kind: manual` element has no shell in its sandbox for
  # install-commands beyond invoking a single prebuilt tool ("Staged
  # artifacts do not provide command 'sh'") — see
  # docs/skills/add-fsdk-component/SKILL.md section 2.
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  # Static prebuilt binary; the automatic FSDK stripper is unavailable in
  # manual-element sandboxes anyway, so just disable it.
  strip-binaries: ""
  # renovate: datasource=github-releases depName=mikefarah/yq
  yq_version: v4.54.3

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "https://github.com/mikefarah/yq/releases/download/%{yq_version}/yq_linux_amd64"
      ref: 129534601871538efe0ba4c5e62a34fb1d5f469bcb975c4fddeb467d82974973
  - arch == "aarch64":
      url: "https://github.com/mikefarah/yq/releases/download/%{yq_version}/yq_linux_arm64"
      ref: 89f69310b61b68d1245065a1241d1fc843f7a36cd6103ffd77ad987613bd1b67
  filename: yq

config:
  install-commands:
  - |
    mkdir -p "%{install-root}/usr/bin"
    cp yq "%{install-root}/usr/bin/yq"
    chmod 755 "%{install-root}/usr/bin/yq"

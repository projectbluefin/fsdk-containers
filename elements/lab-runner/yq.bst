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
  yq_version: v4.53.4

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "https://github.com/mikefarah/yq/releases/download/%{yq_version}/yq_linux_amd64"
          ref: f67d8a6a2dc2308c961f83d5ba8707fd4c7c44ad77902fef87eb3a4646cdfa2a
      - arch == "aarch64":
          url: "https://github.com/mikefarah/yq/releases/download/%{yq_version}/yq_linux_arm64"
          ref: 8c3cf4cff01536588947b6e0ba1544768039e34054cd9ca8a9e4c5706dfb8631
    filename: yq

config:
  install-commands:
    - |
      mkdir -p "%{install-root}/usr/bin"
      cp yq "%{install-root}/usr/bin/yq"
      chmod 755 "%{install-root}/usr/bin/yq"

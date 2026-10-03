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
  yq_version: v4.54.1

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "https://github.com/mikefarah/yq/releases/download/%{yq_version}/yq_linux_amd64"
      ref: 8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f
  - arch == "aarch64":
      url: "https://github.com/mikefarah/yq/releases/download/%{yq_version}/yq_linux_arm64"
      ref: 189088da0c6429ec5178dfaab1a114805f6cab0b61b165ab236efedf1d57a71b
  filename: yq

config:
  install-commands:
  - |
    mkdir -p "%{install-root}/usr/bin"
    cp yq "%{install-root}/usr/bin/yq"
    chmod 755 "%{install-root}/usr/bin/yq"

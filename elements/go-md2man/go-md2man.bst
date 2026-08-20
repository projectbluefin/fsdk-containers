kind: manual
description: |
  Minimal end-to-end proof for the go_module source plugin (issue #113,
  Wave 1). go-md2man v2.0.7 has exactly one dependency
  (github.com/russross/blackfriday/v2 v2.1.0), required directly in
  go.mod: no `// indirect` entries, no replace directives, and its go.mod
  predates the `go 1.14` vendor-consistency threshold. The
  plugin-generated vendor/modules.txt therefore builds unmodified, which
  isolates "does the plugin load/track/fetch/stage at all" from the
  modules.txt and replace-directive traps that larger projects hit
  (documented in docs/skills/go-module-source.md; volcano is the stress
  case).

  Env block is the proven RE-grid Go environment (no network during
  builds): GOROOT must be set explicitly and resolves to the multiarch
  triplet dir /usr/lib/x86_64-linux-gnu/go, NOT /usr/lib/go.

build-depends:
  # FSDK 26.08 removed the shell from runtime-minimal; these commands
  # are shell scripts, so declare the interpreter explicitly.
- freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
- freedesktop-sdk.bst:components/go.bst

variables:
  strip-binaries: ""

environment:
  GOROOT: "%{libdir}/go"
  GOPATH: "%{build-root}/.gopath"
  GOCACHE: "%{build-root}/.gocache"
  GOFLAGS: "-mod=vendor -buildvcs=false"
  CGO_ENABLED: "0"

sources:
  - kind: git_repo
    url: github:cpuguy83/go-md2man.git
    # renovate: datasource=github-tags depName=cpuguy83/go-md2man
    track: v2.0.7
    ref: v2.0.7-0-g061b6c7cbecd6752049221aa15b7a05160796698
  - kind: go_module
    url: github:russross/blackfriday.git
    module: github.com/russross/blackfriday/v2
    # ref filled by 'just bst source track go-md2man/go-md2man.bst':
    # the plugin's track() reads the staged git_repo's go.sum and emits
    # {go-version, git-ref (git-describe), explicit}.
    ref:
      go-version: v2.1.0
      git-ref: v2.1.0-0-g4c9bf9512682b995722660a4196c0013228e2049
      explicit: True

config:
  build-commands:
    - |
      go build -o go-md2man .
    # Smoke test on the grid: the static binary must run in the build
    # sandbox and actually render markdown to roff.
    - |
      smoke="$(echo '# go_module proof' | ./go-md2man)" && echo "${smoke}"
      case "${smoke}" in
        *"go_module proof"*) echo "SMOKE-OK: go-md2man rendered markdown on the grid" ;;
        *) echo "SMOKE-FAIL: unexpected go-md2man output"; exit 1 ;;
      esac

  install-commands:
  - |
    install -Dm755 -t "%{install-root}%{bindir}" go-md2man

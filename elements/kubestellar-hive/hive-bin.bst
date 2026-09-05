kind: manual
description: |
  DRAFT (Wave 0 spike) — build the KubeStellar Hive Go binaries
  (hive, bd, hive-backup) from the pinned kubestellar/hive commit.

  Upstream: https://github.com/kubestellar/hive (module github.com/kubestellar/hive/v2,
  Go module root at v2/ inside the repo). Upstream has NO tags and NO releases;
  the pin below is the v2 branch HEAD as of 2026-08-09. Bump by updating
  `ref:` to a new v2 commit AND refreshing files/go.mod + files/go.sum to
  that commit's v2/go.mod / v2/go.sum.

  MECHANISM: go_module. The Go tree is NOT vendored
  upstream (no v2/vendor/), so dependencies are declared as one
  `kind: go_module` source per module in v2/go.sum (24 modules at this pin).
  The plugin reconstructs a vendor/ tree at stage time (it stages each module
  into vendor/<module> and appends vendor/modules.txt, mimicking
  `go mod vendor`), so the build itself runs fully offline with
  GOPROXY=off -mod=vendor — mandatory on the RE grid, which has no network
  in the build phase.

  PLUGIN STATUS: #145 registered `go_module` in project.conf. The 24 module
  refs below were resolved with `bst source track` from the pinned root
  go.mod/go.sum anchors. A real `go mod vendor` modules.txt is staged too:
  the generated plugin manifest cannot represent this Go 1.25 dependency
  graph's indirect requirements reliably.

  BUILD STATUS (2026-08-24): a full `BST_LOCAL=1 just bst build
  kubestellar-hive/hive-bin.bst` succeeded offline and produced usr/bin/hive,
  usr/bin/bd, and usr/bin/hive-backup. This is degraded local evidence only:
  the test environment had neither the ghost-grid kubeconfig nor kubectl, so
  the #146 grid-build criterion still needs to be rerun where the grid is
  available.

  TWO NON-OBVIOUS WRINKLES Wave 1/4 must know:
  1. go_module.track() (BST_REQUIRES_PREVIOUS_SOURCES_STAGE) reads go.mod and
     go.sum from the PREVIOUS-SOURCES STAGE ROOT. Hive's module lives at
     v2/, so v2/go.sum would NOT be found. The two `kind: local` sources
     below stage pinned copies of v2/go.mod and v2/go.sum AT THE ROOT purely
     as track-time anchors. Keep them in sync with the git pin.
  2. go_module stage() writes vendor/ at the source root; the build moves it
     to v2/vendor before compiling (Go requires vendor/ inside the module
     directory).

  TRACKING: `url:` on each go_module source must be the module's actual git
  repository (vanity paths resolved: go.etcd.io/bbolt -> etcd-io/bbolt,
  golang.org/x/* -> golang/* mirrors, gopkg.in/yaml.v3 -> go-yaml/yaml).
  Track on a workstation (`just bst source track`); the plugin needs network
  at track time for vanity ?go-get=1 lookups and git ref resolution, then
  writes ref: {go-version, git-ref, explicit} into each source. It also tracks
  the leading `git_repo`; restore that ref after tracking unless go.mod,
  go.sum, modules.txt, and the build metadata are all intentionally bumped
  together. Pseudo-version
  modules (go-docx, ledongthuc/pdf, go-qrcode, check.v1) resolve by commit
  sha directly.

  HISTORICAL ESCAPE HATCH if go_module registration regresses: the
  donate-clanker pattern (elements/podman-vm/donate-clanker-worker.bst) — 24
  `kind: git_repo` sources (already-enabled plugin), each with a renovate
  git-refs pin, plus 24 `go mod edit -replace=<module>=../<dir>` lines and
  GOPROXY=off GOSUMDB=off -mod=mod. Verbose but needs no project.conf change.

sources:
- kind: git_repo
  url: github:kubestellar/hive.git
    # renovate: datasource=git-refs depName=kubestellar/hive
  track: v2
    # v2 branch HEAD 2026-08-09 ("fix(style): preserve sanitized theme CSS (#3033)")
  ref: afb7fa610a3ccc9d0b8e259d065708b7359db255

  # Track-time anchors ONLY (wrinkle 1 above): pinned copies of v2/go.mod and
  # v2/go.sum staged at the source root so go_module.track() can resolve
  # module versions. Refresh both when the git pin bumps.
- kind: local
  path: elements/kubestellar-hive/files/go.mod
- kind: local
  path: elements/kubestellar-hive/files/go.sum
- kind: local
  path: elements/kubestellar-hive/files/modules.txt

  # --- go.sum closure at afb7fa6 (24 modules; direct deps marked explicit
  # by track from the anchored go.mod). ---
- kind: go_module
  url: github:fsnotify/fsnotify.git
  module: github.com/fsnotify/fsnotify
  ref:
    go-version: v1.10.1
    git-ref: v1.10.1-0-g76b01a6e8f502187fecedea8b025e79e5a86085c
    explicit: True
- kind: go_module
  url: github:fumiama/go-docx.git
  module: github.com/fumiama/go-docx
  ref:
    go-version: v0.0.0-20250506085032-0c30fd09304b
    git-ref: 0c30fd09304b17fdb42b0dcea142962b2f4883a3
    explicit: True
- kind: go_module
  url: github:fumiama/imgsz.git
  module: github.com/fumiama/imgsz
  ref:
    go-version: v0.0.2
    git-ref: v0.0.2-0-gf0a763b0a34529f370c677b4d4aba20ccb3a1781
    explicit: True
- kind: go_module
  url: github:golang-jwt/jwt.git
  module: github.com/golang-jwt/jwt/v5
  ref:
    go-version: v5.3.1
    git-ref: v5.3.1-0-g7ceae619e739dc8a7bf577214aa8ebf26668e9db
    explicit: True
- kind: go_module
  url: github:google/go-cmp.git
  module: github.com/google/go-cmp
  ref:
    go-version: v0.7.0
    git-ref: v0.7.0-0-g9b12f366a942ebc7254abc7f32ca05068b455fb7
    explicit: False
- kind: go_module
  url: github:google/go-github.git
  module: github.com/google/go-github/v72
  ref:
    go-version: v72.0.0
    git-ref: v72.0.0-0-g718c304661aa42ba7a01da5b54b2ce85f2f48234
    explicit: True
- kind: go_module
  url: github:google/go-querystring.git
  module: github.com/google/go-querystring
  ref:
    go-version: v1.1.0
    git-ref: v1.1.0-0-g1f4a1f9d6e29d314b2513651973fca5c4d4498f1
    explicit: True
- kind: go_module
  url: github:google/uuid.git
  module: github.com/google/uuid
  ref:
    go-version: v1.6.0
    git-ref: v1.6.0-0-g0f11ee6918f41a04c201eceeadf612a377bc7fbc
    explicit: True
- kind: go_module
  url: github:gorilla/websocket.git
  module: github.com/gorilla/websocket
  ref:
    go-version: v1.5.3
    git-ref: v1.5.3-0-gce903f6d1d961af3a8602f2842c8b1c3fca58c4d
    explicit: True
- kind: go_module
  url: github:inconshreveable/mousetrap.git
  module: github.com/inconshreveable/mousetrap
  ref:
    go-version: v1.1.0
    git-ref: v1.1.0-0-g4e8053ee7ef85a6bd26368364a6d27f1641c1d21
    explicit: True
- kind: go_module
  url: github:ledongthuc/pdf.git
  module: github.com/ledongthuc/pdf
  ref:
    go-version: v0.0.0-20250511090121-5959a4027728
    git-ref: 5959a40277285327ee480a3bfd8ec9289fc1ab50
    explicit: True
- kind: go_module
  url: github:pmezard/go-difflib.git
  module: github.com/pmezard/go-difflib
  ref:
    go-version: v1.0.0
    git-ref: v1.0.0-0-g792786c7400a136282c1664665ae0a8db921c6c2
    explicit: False
- kind: go_module
  url: github:robfig/cron.git
  module: github.com/robfig/cron/v3
  ref:
    go-version: v3.0.1
    git-ref: v3.0.1-0-gccba498c397bb90a9c84945bbb0f7af2d72b6309
    explicit: True
- kind: go_module
  url: github:skip2/go-qrcode.git
  module: github.com/skip2/go-qrcode
  ref:
    go-version: v0.0.0-20200617195104-da1b6568686e
    git-ref: da1b6568686e89143e94f980a98bc2dbd5537f13
    explicit: True
- kind: go_module
  url: github:spf13/cobra.git
  module: github.com/spf13/cobra
  ref:
    go-version: v1.10.2
    git-ref: v1.10.2-0-g88b30ab89da2d0d0abb153818746c5a2d30eccec
    explicit: True
- kind: go_module
  url: github:spf13/pflag.git
  module: github.com/spf13/pflag
  ref:
    go-version: v1.0.10
    git-ref: v1.0.10-0-g0491e5702ad2bb108bc519a5221bcc0f52aa9564
    explicit: True
- kind: go_module
  url: github:stretchr/testify.git
  module: github.com/stretchr/testify
  ref:
    go-version: v1.11.1
    git-ref: v1.11.1-0-g2a57335dc9cd6833daa820bc94d9b40c26a7917d
    explicit: False
- kind: go_module
  url: github:davecgh/go-spew.git
  module: github.com/davecgh/go-spew
  ref:
    go-version: v1.1.1
    git-ref: v1.1.1-0-g8991bc29aa16c548c550c7ff78260e27b9ab7c73
    explicit: False
- kind: go_module
  url: github:etcd-io/bbolt.git
  module: go.etcd.io/bbolt
  ref:
    go-version: v1.5.0
    git-ref: v1.5.0-0-ge7a8b2dd498494a3766ba24dd94d3509e5588485
    explicit: True
- kind: go_module
  url: github:golang/sync.git
  module: golang.org/x/sync
  ref:
    go-version: v0.20.0
    git-ref: v0.20.0-0-gec11c4a93de22cde2abe2bf74d70791033c2464c
    explicit: False
- kind: go_module
  url: github:golang/sys.git
  module: golang.org/x/sys
  ref:
    go-version: v0.45.0
    git-ref: v0.45.0-0-g397d5f80920585bc27433d878aba498d062f81e1
    explicit: True
- kind: go_module
  url: github:go-check/check.git
  module: gopkg.in/check.v1
  ref:
    go-version: v0.0.0-20161208181325-20d25e280405
    git-ref: 20d25e2804050c1cd24a7eea1e7a6447dd0e74ec
    explicit: False
- kind: go_module
  url: github:natefinch/lumberjack.git
  module: gopkg.in/natefinch/lumberjack.v2
  ref:
    go-version: v2.2.1
    git-ref: v2.2.1-0-g4cb27fcfbb0f35cb48c542c5ea80b7c1d18933d0
    explicit: True
- kind: go_module
  url: github:go-yaml/yaml.git
  module: gopkg.in/yaml.v3

  ref:
    go-version: v3.0.1
    git-ref: v3.0.1-0-gf6f7691b1fdeb513f56608cd2c32c51f8194bf51
    explicit: True
build-depends:
  # runtime-gnu provides the shell for these commands (FSDK 26.08 removed it
  # from runtime-minimal).
- freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
- freedesktop-sdk.bst:components/go.bst

variables:
  strip-binaries: ""
  # Git metadata stamped into the binary, mirroring upstream's ldflags.
  hive-git-hash: afb7fa610a3ccc9d0b8e259d065708b7359db255
  hive-git-short: afb7fa6
  hive-git-branch: v2

config:
  build-commands:
  - |
    # The plugin-generated manifest cannot faithfully reproduce indirect
    # requirements. Use the pinned `go mod vendor` output instead.
    mv -vf modules.txt vendor/modules.txt
    # Wrinkle 2: go_module staged vendor/ at the source root; the module
    # root is v2/. Move the reconstructed vendor tree into the module.
    mv vendor v2/vendor
    # Drop the track-time anchors so they cannot confuse the toolchain.
    rm -f go.mod go.sum
    cd v2
    # GOROOT: FSDK's components/go.bst installs to %{libdir}/go, i.e. the
    # MULTIARCH TRIPLET dir (/usr/lib/x86_64-linux-gnu/go). Never reference
    # a bare /usr/lib/go (elements/go/go-stack.bst note; mandatory on the
    # RE grid). GOPROXY=off + -mod=vendor: the grid build phase has NO
    # network — everything must come from the staged vendor tree.
    export GOROOT="%{libdir}/go"
    export GOPATH="$PWD/.gopath"
    export GOCACHE="$PWD/.gocache"
    export GOPROXY=off GOSUMDB=off GOFLAGS=-mod=vendor CGO_ENABLED=0
    for cmd in hive bd hive-backup; do
      go build -trimpath -buildvcs=false \
        -ldflags="-s -w -X main.gitHash=%{hive-git-hash} -X main.gitShort=%{hive-git-short} -X main.gitBranch=%{hive-git-branch}" \
        -o "../bin/$cmd" "./cmd/$cmd"
    done

  install-commands:
  - |
    for cmd in hive bd hive-backup; do
      install -D -m 755 "bin/$cmd" "%{install-root}%{bindir}/$cmd"
    done

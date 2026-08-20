kind: manual
description: |
  DRAFT (Wave 0 spike) — build the KubeStellar Hive Go binaries
  (hive, bd, hive-backup) from the pinned kubestellar/hive commit.

  Upstream: https://github.com/kubestellar/hive (module github.com/kubestellar/hive/v2,
  Go module root at v2/ inside the repo). Upstream has NO tags and NO releases;
  the pin below is the v2 branch HEAD as of 2026-08-09. Bump by updating
  `ref:` to a new v2 commit AND refreshing files/go.mod + files/go.sum to
  that commit's v2/go.mod / v2/go.sum.

  MECHANISM: go_module (BLOCKED — see below). The Go tree is NOT vendored
  upstream (no v2/vendor/), so dependencies are declared as one
  `kind: go_module` source per module in v2/go.sum (24 modules at this pin).
  The plugin reconstructs a vendor/ tree at stage time (it stages each module
  into vendor/<module> and appends vendor/modules.txt, mimicking
  `go mod vendor`), so the build itself runs fully offline with
  GOPROXY=off -mod=vendor — mandatory on the RE grid, which has no network
  in the build phase.

  KNOWN BLOCKER (Wave 1 owns the fix): project.conf junctions
  buildstream-plugins-community 2.3.1 but enables only `git_repo` and
  `patch_queue` under `sources:`. `go_module` ships in that tarball
  (src/buildstream_plugins_community/sources/go_module.py, confirmed) but is
  not registered, so this element fails at LOAD time. Verbatim error,
  measured 2026-08-09 on the ghost grid
  (`just bst show --deps none kubestellar-hive/kubestellar-hive-stack.bst`):

      kubestellar-hive/hive-bin.bst [line 79 column 4]: No source plugin
      registered for kind 'go_module'

  (line 79 is the first `kind: go_module` source below; the line number
  drifts as the description is edited — the kind string is the invariant
  part.) Do NOT edit project.conf from this lane.

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
  writes ref: {go-version, git-ref, explicit} into each source. Pseudo-version
  modules (go-docx, ledongthuc/pdf, go-qrcode, check.v1) resolve by commit
  sha directly.

  ESCAPE HATCH if go_module cannot be enabled: the donate-clanker pattern
  (elements/podman-vm/donate-clanker-worker.bst) — 24 `kind: git_repo`
  sources (already-enabled plugin), each with a renovate git-refs pin, plus
  24 `go mod edit -replace=<module>=../<dir>` lines and
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

  # --- go.sum closure at afb7fa6 (24 modules; direct deps marked explicit
  # by track from the anchored go.mod). refs pending `bst source track`
  # once Wave 1 enables go_module. ---
  - kind: go_module
    url: github:fsnotify/fsnotify.git
    module: github.com/fsnotify/fsnotify
  - kind: go_module
    url: github:fumiama/go-docx.git
    module: github.com/fumiama/go-docx
  - kind: go_module
    url: github:fumiama/imgsz.git
    module: github.com/fumiama/imgsz
  - kind: go_module
    url: github:golang-jwt/jwt.git
    module: github.com/golang-jwt/jwt/v5
  - kind: go_module
    url: github:google/go-cmp.git
    module: github.com/google/go-cmp
  - kind: go_module
    url: github:google/go-github.git
    module: github.com/google/go-github/v72
  - kind: go_module
    url: github:google/go-querystring.git
    module: github.com/google/go-querystring
  - kind: go_module
    url: github:google/uuid.git
    module: github.com/google/uuid
  - kind: go_module
    url: github:gorilla/websocket.git
    module: github.com/gorilla/websocket
  - kind: go_module
    url: github:inconshreveable/mousetrap.git
    module: github.com/inconshreveable/mousetrap
  - kind: go_module
    url: github:ledongthuc/pdf.git
    module: github.com/ledongthuc/pdf
  - kind: go_module
    url: github:pmezard/go-difflib.git
    module: github.com/pmezard/go-difflib
  - kind: go_module
    url: github:robfig/cron.git
    module: github.com/robfig/cron/v3
  - kind: go_module
    url: github:skip2/go-qrcode.git
    module: github.com/skip2/go-qrcode
  - kind: go_module
    url: github:spf13/cobra.git
    module: github.com/spf13/cobra
  - kind: go_module
    url: github:spf13/pflag.git
    module: github.com/spf13/pflag
  - kind: go_module
    url: github:stretchr/testify.git
    module: github.com/stretchr/testify
  - kind: go_module
    url: github:davecgh/go-spew.git
    module: github.com/davecgh/go-spew
  - kind: go_module
    url: github:etcd-io/bbolt.git
    module: go.etcd.io/bbolt
  - kind: go_module
    url: github:golang/sync.git
    module: golang.org/x/sync
  - kind: go_module
    url: github:golang/sys.git
    module: golang.org/x/sys
  - kind: go_module
    url: github:go-check/check.git
    module: gopkg.in/check.v1
  - kind: go_module
    url: github:natefinch/lumberjack.git
    module: gopkg.in/natefinch/lumberjack.v2
  - kind: go_module
    url: github:go-yaml/yaml.git
    module: gopkg.in/yaml.v3

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

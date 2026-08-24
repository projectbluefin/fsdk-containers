kind: manual
description: |
  Build volcano's control-plane binaries from source.

  Upstream: https://github.com/volcano-sh/volcano (CNCF batch scheduler).
  Ships the three control-plane binaries the upstream Helm chart deploys:
  vc-scheduler, vc-controller-manager, vc-webhook-manager.
  Out of scope for this image: vc-agent / vc-agent-scheduler (run
  privileged on nodes, own lifecycle) and vcctl (a CLI, future image).

  DEPENDENCY MODEL (issue #113): volcano does NOT vendor its dependencies
  upstream, so this element uses one `go_module` source per vendored
  module below (235 entries, generated from `go mod vendor` output at the
  pinned tag). It follows FSDK's fscrypt.bst / git-lfs.bst pattern:
  go_module sources stage vendor/<module>/, then the authoritative
  `go mod vendor`-generated modules.txt (files/modules.txt, staged as a
  local source) overwrites the plugin-appended one at build time. The
  shipped modules.txt is REQUIRED: volcano's go.mod has 37 replace
  directives which the plugin does not record in vendor/modules.txt, and
  go's vendor consistency check would fail without them.

  GATE STATUS: OPEN. `go_module` IS enabled — project.conf registers it
  under the plugins/buildstream-plugins-community.bst junction's
  `sources:` list, landed by #145 (commit d36af3c) which closed #144.
  This element no longer fails to load for that reason.

  The text this replaced said "BLOCKED until Wave 1 enables go_module ...
  fails to load with 'unknown source kind' -- expected", which stopped
  being true in the very commit that added this file: #145 enabled the
  plugin and shipped this element in one change, and only the prose was
  left behind. It cost the next reader a re-derivation, so it is stated
  positively here rather than deleted.

  REMAINING WORK for the #146 spike (steps 1-3 of the old finish line,
  minus the step that is done):
    1. DONE — project.conf registers `go_module`.
    2. TODO — `bst source track volcano/volcano.bst` to fill every `ref:`
       from go.sum (the plugin's track() reads the staged git_repo's
       go.sum; refs come out in git-describe form). As of this commit
       232 of the 235 go_module sources still carry the placeholder
       comment `# ref: {...} filled by 'bst source track'` and NO real
       `ref:`, so the element cannot build yet. Two entries need
       hand-filled refs -- see their comments (cyphar.com/go-pathrs:
       plugin track crashes on its 4-field go-import meta;
       stathat.com/c/consistent: vanity domain defunct). Tracking needs
       network for vanity ?go-get=1 lookups, so it cannot run in the
       grid build phase.
    3. TODO — `just bst build volcano/volcano-stack.bst`. Everything else
       was already proven in Wave 0 with a `go mod vendor` tarball staged
       via a local source (identical vendor layout): the FSDK go
       toolchain (GOROOT=%{libdir}/go), the env block below, and these
       exact build/install commands produced working statically-linked
       binaries on the ghost grid (vc-scheduler --version reported
       Version: v1.15.1, Git SHA: 0a56ed33...). Note that Wave 0's go
       spike (#186) corrected the toolchain version: the FSDK component
       is go1.26.6 at junction ref 26.08rc.1, not the go1.26.5 this note
       previously cited.

  Environment notes (RE grid has no network during builds):
  - GOROOT is set explicitly: mandatory on the ghost BuildBarn grid.
  - GOPATH/GOCACHE are pinned under %{build-root} (writable in sandbox).
  - GOFLAGS=-mod=vendor -buildvcs=false: never touch the network or VCS.
  - CGO_ENABLED=0 matches upstream's Makefile for these binaries
    (fully static; no gcc needed at build time).
  - ldflags mirror Makefile.def (GitSHA/Version -X stamps); the upstream
    `Built` date stamp is deliberately omitted for reproducible builds.

  GRID NOTE: builds currently need BST_FLAGS="--cache-buildtrees never";
  the default buildtree-caching path intermittently fails with
  'Failed to obtain input file ...: Shard N: Object not found'
  (ghost bb-storage shard sync issue -- see the Wave 0 report).

build-depends:
  # FSDK 26.08 removed the shell from runtime-minimal; these commands
  # are shell scripts, so declare the interpreter explicitly.
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/go.bst

variables:
  strip-binaries: ""
  volcano-version: "v1.15.1"
  volcano-git-sha: "0a56ed331897f5455916a44d3075671376d731d6"

environment:
  GOROOT: "%{libdir}/go"
  GOPATH: "%{build-root}/.gopath"
  GOCACHE: "%{build-root}/.gocache"
  GOFLAGS: "-mod=vendor -buildvcs=false"
  CGO_ENABLED: "0"

sources:
  - kind: git_repo
    url: github:volcano-sh/volcano.git
    # renovate: datasource=github-tags depName=volcano-sh/volcano
    track: v1.15.1
    ref: v1.15.1-0-g0a56ed331897f5455916a44d3075671376d731d6
  # Authoritative vendor manifest from `go mod vendor` at the pinned tag
  # (handles the 37 replace directives the go_module plugin cannot
  # record). Regenerate when bumping: clone tag, `go mod vendor`, copy
  # vendor/modules.txt here.
  - kind: local
    path: elements/volcano/files/modules.txt
  # --- go_module sources: one per vendored module ---------------------
  # Generated from vendor/modules.txt at v1.15.1 (module set == what
  # `go mod vendor` stages; go.sum-only entries like test-only hashes
  # are deliberately absent). URLs resolved via ?go-get=1 meta tags,
  # same as the plugin's own get_module_subdirectory().
  # Every `ref:` is filled by `bst source track` in Wave 1; the
  # informational comment records the expected go-version/explicit so a
  # bad track result is easy to spot.
  - kind: go_module
    url: github:cel-expr/cel-spec.git
    module: cel.dev/expr
    # go-version: v0.25.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:AdaLogics/go-fuzz-headers.git
    module: github.com/AdaLogics/go-fuzz-headers
    # go-version: v0.0.0-20240806141605-e8a1dd7889d6 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:Azure/go-ansiterm.git
    module: github.com/Azure/go-ansiterm
    # go-version: v0.0.0-20230124172434-306776ec8161 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:JeffAshton/win_pdh.git
    module: github.com/JeffAshton/win_pdh
    # go-version: v0.0.0-20161109143554-76bb4ee9f0ab explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:MakeNowJust/heredoc.git
    module: github.com/MakeNowJust/heredoc
    # go-version: v1.0.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:Masterminds/semver.git
    module: github.com/Masterminds/semver/v3
    # go-version: v3.4.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:Microsoft/go-winio.git
    module: github.com/Microsoft/go-winio
    # go-version: v0.6.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:Microsoft/hnslib.git
    module: github.com/Microsoft/hnslib
    # go-version: v0.1.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:NYTimes/gziphandler.git
    module: github.com/NYTimes/gziphandler
    # go-version: v1.1.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:agiledragon/gomonkey.git
    module: github.com/agiledragon/gomonkey/v2
    # go-version: v2.11.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:antlr4-go/antlr.git
    module: github.com/antlr4-go/antlr/v4
    # go-version: v4.13.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:armon/circbuf.git
    module: github.com/armon/circbuf
    # go-version: v0.0.0-20190214190532-5111143e8da2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:beorn7/perks.git
    module: github.com/beorn7/perks
    # go-version: v1.0.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:blang/semver.git
    module: github.com/blang/semver/v4
    # go-version: v4.0.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:cenkalti/backoff.git
    module: github.com/cenkalti/backoff/v5
    # go-version: v5.0.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:cespare/xxhash.git
    module: github.com/cespare/xxhash/v2
    # go-version: v2.3.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:chai2010/gettext-go.git
    module: github.com/chai2010/gettext-go
    # go-version: v1.0.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:cilium/ebpf.git
    module: github.com/cilium/ebpf
    # go-version: v0.17.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:container-storage-interface/spec.git
    module: github.com/container-storage-interface/spec
    # go-version: v1.9.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:containerd/containerd.git
    module: github.com/containerd/containerd/api
    # go-version: v1.9.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:containerd/errdefs.git
    module: github.com/containerd/errdefs
    # go-version: v1.0.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:containerd/errdefs.git
    module: github.com/containerd/errdefs/pkg
    # go-version: v0.3.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:containerd/log.git
    module: github.com/containerd/log
    # go-version: v0.1.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:containerd/ttrpc.git
    module: github.com/containerd/ttrpc
    # go-version: v1.2.7 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:containerd/typeurl.git
    module: github.com/containerd/typeurl/v2
    # go-version: v2.2.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:containernetworking/cni.git
    module: github.com/containernetworking/cni
    # go-version: v1.1.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:containernetworking/plugins.git
    module: github.com/containernetworking/plugins
    # go-version: v1.1.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:coreos/go-semver.git
    module: github.com/coreos/go-semver
    # go-version: v0.3.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:coreos/go-systemd.git
    module: github.com/coreos/go-systemd/v22
    # go-version: v22.6.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:cyphar/filepath-securejoin.git
    module: github.com/cyphar/filepath-securejoin
    # go-version: v0.6.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:davecgh/go-spew.git
    module: github.com/davecgh/go-spew
    # go-version: v1.1.2-0.20180830191138-d8f796af33cc explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:distribution/reference.git
    module: github.com/distribution/reference
    # go-version: v0.6.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:docker/go-units.git
    module: github.com/docker/go-units
    # go-version: v0.5.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:elastic/go-elasticsearch.git
    module: github.com/elastic/go-elasticsearch/v7
    # go-version: v7.17.7 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:emicklei/go-restful.git
    module: github.com/emicklei/go-restful/v3
    # go-version: v3.12.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:euank/go-kmsg-parser.git
    module: github.com/euank/go-kmsg-parser
    # go-version: v2.0.0+incompatible explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:evanphx/json-patch.git
    module: github.com/evanphx/json-patch/v5
    # go-version: v5.9.11 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:exponent-io/jsonpath.git
    module: github.com/exponent-io/jsonpath
    # go-version: v0.0.0-20210407135951-1de76d718b3f explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:fatih/camelcase.git
    module: github.com/fatih/camelcase
    # go-version: v1.0.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:felixge/httpsnoop.git
    module: github.com/felixge/httpsnoop
    # go-version: v1.0.4 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:fsnotify/fsnotify.git
    module: github.com/fsnotify/fsnotify
    # go-version: v1.9.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:fxamacker/cbor.git
    module: github.com/fxamacker/cbor/v2
    # go-version: v2.9.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-errors/errors.git
    module: github.com/go-errors/errors
    # go-version: v1.4.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-logr/logr.git
    module: github.com/go-logr/logr
    # go-version: v1.4.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-logr/stdr.git
    module: github.com/go-logr/stdr
    # go-version: v1.2.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/jsonpointer.git
    module: github.com/go-openapi/jsonpointer
    # go-version: v0.22.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/jsonreference.git
    module: github.com/go-openapi/jsonreference
    # go-version: v0.21.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/cmdutils
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/conv
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/fileutils
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/jsonname
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/jsonutils
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/loading
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/mangling
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/netutils
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/stringutils
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/typeutils
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/yamlutils
    # go-version: v0.25.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:go-task/slim-sprig.git
    module: github.com/go-task/slim-sprig/v3
    # go-version: v3.0.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:godbus/dbus.git
    module: github.com/godbus/dbus/v5
    # go-version: v5.1.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:gogo/protobuf.git
    module: github.com/gogo/protobuf
    # go-version: v1.3.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:golang/mock.git
    module: github.com/golang/mock
    # go-version: v1.6.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:golang/protobuf.git
    module: github.com/golang/protobuf
    # go-version: v1.5.4 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:google/btree.git
    module: github.com/google/btree
    # go-version: v1.1.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:google/cadvisor.git
    module: github.com/google/cadvisor
    # go-version: v0.53.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:google/cel-go.git
    module: github.com/google/cel-go
    # go-version: v0.26.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:google/gnostic-models.git
    module: github.com/google/gnostic-models
    # go-version: v0.7.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:google/go-cmp.git
    module: github.com/google/go-cmp
    # go-version: v0.7.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:google/pprof.git
    module: github.com/google/pprof
    # go-version: v0.0.0-20260302011040-a15ffb7f9dcc explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:google/shlex.git
    module: github.com/google/shlex
    # go-version: v0.0.0-20191202100458-e7afc7fbc510 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:google/uuid.git
    module: github.com/google/uuid
    # go-version: v1.6.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:gorilla/websocket.git
    module: github.com/gorilla/websocket
    # go-version: v1.5.4-0.20250319132907-e064f32e3674 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:grafana/regexp.git
    module: github.com/grafana/regexp
    # go-version: v0.0.0-20250905093917-f7b3be9d1853 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:gregjones/httpcache.git
    module: github.com/gregjones/httpcache
    # go-version: v0.0.0-20190611155906-901d90724c79 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:grpc-ecosystem/go-grpc-prometheus.git
    module: github.com/grpc-ecosystem/go-grpc-prometheus
    # go-version: v1.2.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:grpc-ecosystem/grpc-gateway.git
    module: github.com/grpc-ecosystem/grpc-gateway/v2
    # go-version: v2.28.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:hashicorp/errwrap.git
    module: github.com/hashicorp/errwrap
    # go-version: v1.1.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:hashicorp/go-multierror.git
    module: github.com/hashicorp/go-multierror
    # go-version: v1.1.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:imdario/mergo.git
    module: github.com/imdario/mergo
    # go-version: v0.3.16 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:inconshreveable/mousetrap.git
    module: github.com/inconshreveable/mousetrap
    # go-version: v1.1.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:json-iterator/go.git
    module: github.com/json-iterator/go
    # go-version: v1.1.12 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:karrick/godirwalk.git
    module: github.com/karrick/godirwalk
    # go-version: v1.17.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kylelemons/godebug.git
    module: github.com/kylelemons/godebug
    # go-version: v1.1.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:liggitt/tabwriter.git
    module: github.com/liggitt/tabwriter
    # go-version: v0.0.0-20181228230101-89fcab3d43de explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  # DISABLED-DURING-TRACK: - kind: go_module
    # DISABLED-DURING-TRACK: url: github:mistifyio/go-zfs.git
    # DISABLED-DURING-TRACK: module: github.com/mistifyio/go-zfs
    # DISABLED-DURING-TRACK: # go-version: v2.1.2-0.20190413222219-f784269be439+incompatible explicit: True
    # DISABLED-DURING-TRACK: # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:mitchellh/go-wordwrap.git
    module: github.com/mitchellh/go-wordwrap
    # go-version: v1.0.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:mitchellh/mapstructure.git
    module: github.com/mitchellh/mapstructure
    # go-version: v1.5.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:moby/spdystream.git
    module: github.com/moby/spdystream
    # go-version: v0.5.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:moby/sys.git
    module: github.com/moby/sys/mountinfo
    # go-version: v0.7.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:moby/sys.git
    module: github.com/moby/sys/userns
    # go-version: v0.1.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:moby/term.git
    module: github.com/moby/term
    # go-version: v0.5.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:modern-go/concurrent.git
    module: github.com/modern-go/concurrent
    # go-version: v0.0.0-20180306012644-bacd9c7ef1dd explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:modern-go/reflect2.git
    module: github.com/modern-go/reflect2
    # go-version: v1.0.3-0.20250322232337-35a7c28c31ee explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:monochromegane/go-gitignore.git
    module: github.com/monochromegane/go-gitignore
    # go-version: v0.0.0-20200626010858-205db1a8cc00 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:munnerz/goautoneg.git
    module: github.com/munnerz/goautoneg
    # go-version: v0.0.0-20191010083416-a7dc8b61c822 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:mxk/go-flowrate.git
    module: github.com/mxk/go-flowrate
    # go-version: v0.0.0-20140419014527-cca7078d478f explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:onsi/ginkgo.git
    module: github.com/onsi/ginkgo/v2
    # go-version: v2.27.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:onsi/gomega.git
    module: github.com/onsi/gomega
    # go-version: v1.38.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:opencontainers/cgroups.git
    module: github.com/opencontainers/cgroups
    # go-version: v0.0.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:opencontainers/go-digest.git
    module: github.com/opencontainers/go-digest
    # go-version: v1.0.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:opencontainers/image-spec.git
    module: github.com/opencontainers/image-spec
    # go-version: v1.1.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:opencontainers/runtime-spec.git
    module: github.com/opencontainers/runtime-spec
    # go-version: v1.2.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:opencontainers/selinux.git
    module: github.com/opencontainers/selinux
    # go-version: v1.13.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:peterbourgon/diskv.git
    module: github.com/peterbourgon/diskv
    # go-version: v2.0.1+incompatible explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:pkg/errors.git
    module: github.com/pkg/errors
    # go-version: v0.9.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:pmezard/go-difflib.git
    module: github.com/pmezard/go-difflib
    # go-version: v1.0.1-0.20181226105442-5d4384ee4fb2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:prometheus/client_golang.git
    module: github.com/prometheus/client_golang
    # go-version: v1.23.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:prometheus/client_model.git
    module: github.com/prometheus/client_model
    # go-version: v0.6.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:prometheus/common.git
    module: github.com/prometheus/common
    # go-version: v0.67.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:prometheus/procfs.git
    module: github.com/prometheus/procfs
    # go-version: v0.16.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:prometheus/prometheus.git
    module: github.com/prometheus/prometheus
    # go-version: v0.311.2-0.20260410083055-07c6232d159b explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:robfig/cron.git
    module: github.com/robfig/cron/v3
    # go-version: v3.0.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:russross/blackfriday.git
    module: github.com/russross/blackfriday/v2
    # go-version: v2.1.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:sirupsen/logrus.git
    module: github.com/sirupsen/logrus
    # go-version: v1.9.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:spf13/cobra.git
    module: github.com/spf13/cobra
    # go-version: v1.10.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:spf13/pflag.git
    module: github.com/spf13/pflag
    # go-version: v1.0.10 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:stoewer/go-strcase.git
    module: github.com/stoewer/go-strcase
    # go-version: v1.3.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:stretchr/testify.git
    module: github.com/stretchr/testify
    # go-version: v1.11.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:vishvananda/netlink.git
    module: github.com/vishvananda/netlink
    # go-version: v1.3.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:vishvananda/netns.git
    module: github.com/vishvananda/netns
    # go-version: v0.0.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:x448/float16.git
    module: github.com/x448/float16
    # go-version: v0.8.4 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:xlab/treeprint.git
    module: github.com/xlab/treeprint
    # go-version: v1.2.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:etcd-io/etcd.git
    module: go.etcd.io/etcd/api/v3
    # go-version: v3.6.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:etcd-io/etcd.git
    module: go.etcd.io/etcd/client/pkg/v3
    # go-version: v3.6.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:etcd-io/etcd.git
    module: go.etcd.io/etcd/client/v3
    # go-version: v3.6.5 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go-instrumentation.git
    module: go.opentelemetry.io/auto/sdk
    # go-version: v1.2.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go-contrib.git
    module: go.opentelemetry.io/contrib/instrumentation/github.com/emicklei/go-restful/otelrestful
    # go-version: v0.44.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go-contrib.git
    module: go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc
    # go-version: v0.60.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go-contrib.git
    module: go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
    # go-version: v0.67.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel
    # go-version: v1.43.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel/exporters/otlp/otlptrace
    # go-version: v1.42.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc
    # go-version: v1.42.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel/metric
    # go-version: v1.43.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel/sdk
    # go-version: v1.43.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel/trace
    # go-version: v1.43.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-proto-go.git
    module: go.opentelemetry.io/proto/otlp
    # go-version: v1.9.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:uber-go/automaxprocs.git
    module: go.uber.org/automaxprocs
    # go-version: v1.6.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:uber-go/multierr.git
    module: go.uber.org/multierr
    # go-version: v1.11.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:uber-go/zap.git
    module: go.uber.org/zap
    # go-version: v1.27.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:yaml/go-yaml.git
    module: go.yaml.in/yaml/v2
    # go-version: v2.4.4 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:yaml/go-yaml.git
    module: go.yaml.in/yaml/v3
    # go-version: v3.0.4 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/crypto
    module: golang.org/x/crypto
    # go-version: v0.53.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/exp
    module: golang.org/x/exp
    # go-version: v0.0.0-20260218203240-3dfff04db8fa explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/mod
    module: golang.org/x/mod
    # go-version: v0.36.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/net
    module: golang.org/x/net
    # go-version: v0.55.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/oauth2
    module: golang.org/x/oauth2
    # go-version: v0.36.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/sync
    module: golang.org/x/sync
    # go-version: v0.21.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/sys
    module: golang.org/x/sys
    # go-version: v0.46.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/term
    module: golang.org/x/term
    # go-version: v0.44.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/text
    module: golang.org/x/text
    # go-version: v0.38.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/time
    module: golang.org/x/time
    # go-version: v0.15.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/tools
    module: golang.org/x/tools
    # go-version: v0.45.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:googleapis/go-genproto.git
    module: google.golang.org/genproto/googleapis/api
    # go-version: v0.0.0-20260319201613-d00831a3d3e7 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:googleapis/go-genproto.git
    module: google.golang.org/genproto/googleapis/rpc
    # go-version: v0.0.0-20260311181403-84a4fc48630c explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:grpc/grpc-go.git
    module: google.golang.org/grpc
    # go-version: v1.79.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://go.googlesource.com/protobuf
    module: google.golang.org/protobuf
    # go-version: v1.36.11 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://gopkg.in/evanphx/json-patch.v4
    module: gopkg.in/evanphx/json-patch.v4
    # go-version: v4.13.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://gopkg.in/inf.v0
    module: gopkg.in/inf.v0
    # go-version: v0.9.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://gopkg.in/natefinch/lumberjack.v2
    module: gopkg.in/natefinch/lumberjack.v2
    # go-version: v2.2.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://gopkg.in/yaml.v2
    module: gopkg.in/yaml.v2
    # go-version: v2.4.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: https://gopkg.in/yaml.v3
    module: gopkg.in/yaml.v3
    # go-version: v3.0.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/api.git
    module: k8s.io/api
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/apiextensions-apiserver.git
    module: k8s.io/apiextensions-apiserver
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/apimachinery.git
    module: k8s.io/apimachinery
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/apiserver.git
    module: k8s.io/apiserver
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/cli-runtime.git
    module: k8s.io/cli-runtime
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/client-go.git
    module: k8s.io/client-go
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/cloud-provider.git
    module: k8s.io/cloud-provider
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/code-generator.git
    module: k8s.io/code-generator
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/component-base.git
    module: k8s.io/component-base
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/component-helpers.git
    module: k8s.io/component-helpers
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/controller-manager.git
    module: k8s.io/controller-manager
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/cri-api.git
    module: k8s.io/cri-api
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/cri-client.git
    module: k8s.io/cri-client
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/csi-translation-lib.git
    module: k8s.io/csi-translation-lib
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/dynamic-resource-allocation.git
    module: k8s.io/dynamic-resource-allocation
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/gengo.git
    module: k8s.io/gengo/v2
    # go-version: v2.0.0-20250922181213-ec3ebc5fd46b explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/klog.git
    module: k8s.io/klog/v2
    # go-version: v2.140.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kms.git
    module: k8s.io/kms
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kube-openapi.git
    module: k8s.io/kube-openapi
    # go-version: v0.0.0-20250910181357-589584f1c912 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kube-scheduler.git
    module: k8s.io/kube-scheduler
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kubectl.git
    module: k8s.io/kubectl
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kubelet.git
    module: k8s.io/kubelet
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kubernetes.git
    module: k8s.io/kubernetes
    # go-version: v1.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/metrics.git
    module: k8s.io/metrics
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/mount-utils.git
    module: k8s.io/mount-utils
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/pod-security-admission.git
    module: k8s.io/pod-security-admission
    # go-version: v0.35.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/utils.git
    module: k8s.io/utils
    # go-version: v0.0.0-20251002143259-bc988d571ff4 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes-sigs/apiserver-network-proxy.git
    module: sigs.k8s.io/apiserver-network-proxy/konnectivity-client
    # go-version: v0.31.2 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes-sigs/controller-runtime.git
    module: sigs.k8s.io/controller-runtime
    # go-version: v0.23.3 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes-sigs/e2e-framework.git
    module: sigs.k8s.io/e2e-framework
    # go-version: v0.6.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes-sigs/json.git
    module: sigs.k8s.io/json
    # go-version: v0.0.0-20250730193827-2d320260d730 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes-sigs/kustomize.git
    module: sigs.k8s.io/kustomize/api
    # go-version: v0.20.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes-sigs/kustomize.git
    module: sigs.k8s.io/kustomize/kyaml
    # go-version: v0.20.1 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes-sigs/randfill.git
    module: sigs.k8s.io/randfill
    # go-version: v1.0.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes-sigs/structured-merge-diff.git
    module: sigs.k8s.io/structured-merge-diff/v6
    # go-version: v6.3.2-0.20260122202528-d9cc6641c482 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes-sigs/yaml.git
    module: sigs.k8s.io/yaml
    # go-version: v1.6.0 explicit: True
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:googleapis/google-cloud-go.git
    module: cloud.google.com/go
    # go-version: v0.100.2 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc
    # go-version: v1.42.0 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:grpc/grpc-go.git
    module: google.golang.org/grpc
    # go-version: v1.79.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/api.git
    module: k8s.io/api
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/apiextensions-apiserver.git
    module: k8s.io/apiextensions-apiserver
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/apimachinery.git
    module: k8s.io/apimachinery
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/apiserver.git
    module: k8s.io/apiserver
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/cli-runtime.git
    module: k8s.io/cli-runtime
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/client-go.git
    module: k8s.io/client-go
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/cloud-provider.git
    module: k8s.io/cloud-provider
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/cluster-bootstrap.git
    module: k8s.io/cluster-bootstrap
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/code-generator.git
    module: k8s.io/code-generator
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/component-base.git
    module: k8s.io/component-base
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/component-helpers.git
    module: k8s.io/component-helpers
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/controller-manager.git
    module: k8s.io/controller-manager
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/cri-api.git
    module: k8s.io/cri-api
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/cri-client.git
    module: k8s.io/cri-client
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/csi-translation-lib.git
    module: k8s.io/csi-translation-lib
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/dynamic-resource-allocation.git
    module: k8s.io/dynamic-resource-allocation
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/endpointslice.git
    module: k8s.io/endpointslice
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/externaljwt.git
    module: k8s.io/externaljwt
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kube-aggregator.git
    module: k8s.io/kube-aggregator
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kube-controller-manager.git
    module: k8s.io/kube-controller-manager
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kube-proxy.git
    module: k8s.io/kube-proxy
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kube-scheduler.git
    module: k8s.io/kube-scheduler
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kubectl.git
    module: k8s.io/kubectl
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/kubelet.git
    module: k8s.io/kubelet
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/legacy-cloud-providers.git
    module: k8s.io/legacy-cloud-providers
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/metrics.git
    module: k8s.io/metrics
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/mount-utils.git
    module: k8s.io/mount-utils
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/node-api.git
    module: k8s.io/node-api
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/pod-security-admission.git
    module: k8s.io/pod-security-admission
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/sample-apiserver.git
    module: k8s.io/sample-apiserver
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/sample-cli-plugin.git
    module: k8s.io/sample-cli-plugin
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  - kind: go_module
    url: github:kubernetes/sample-controller.git
    module: k8s.io/sample-controller
    # go-version: v0.35.3 explicit: False
    # ref: {...} filled by 'bst source track' (Wave 1)
  # DISABLED-DURING-TRACK: - kind: go_module
    # DISABLED-DURING-TRACK: url: github:cyphar/libpathrs.git
    # DISABLED-DURING-TRACK: module: cyphar.com/go-pathrs
    # DISABLED-DURING-TRACK: # go-version: v0.2.1 explicit: True
    # DISABLED-DURING-TRACK: # Module lives in the go-pathrs/ subdir of cyphar/libpathrs (tagged
    # DISABLED-DURING-TRACK: # go-pathrs/vX.Y.Z). The plugin's track() will CRASH here: this module's
    # DISABLED-DURING-TRACK: # go-import meta has a non-standard 4th field
    # DISABLED-DURING-TRACK: # ("cyphar.com/go-pathrs git https://github.com/cyphar/libpathrs.git go-pathrs")
    # DISABLED-DURING-TRACK: # and get_module_subdirectory() does an unpack of exactly 3 fields.
    # DISABLED-DURING-TRACK: # Hand-written ref (Wave 1, verified against refs/tags/go-pathrs/v0.2.1):
    # DISABLED-DURING-TRACK: ref:
      # DISABLED-DURING-TRACK: go-version: v0.2.1
      # DISABLED-DURING-TRACK: git-ref: go-pathrs/v0.2.1-0-g6416ad69fa96f5465642b20af55f9e677b1d5d1d
      # DISABLED-DURING-TRACK: explicit: True
      # DISABLED-DURING-TRACK: subdirectory: go-pathrs
  # DISABLED-DURING-TRACK: - kind: go_module
    # DISABLED-DURING-TRACK: url: github:stathat/consistent.git
    # DISABLED-DURING-TRACK: module: stathat.com/c/consistent
    # DISABLED-DURING-TRACK: # go-version: v1.0.0 explicit: True
    # DISABLED-DURING-TRACK: # stathat.com is defunct so ?go-get=1 no longer resolves; historical
    # DISABLED-DURING-TRACK: # mapping is github.com/stathat/consistent (tag v1.0.0 exists).
    # DISABLED-DURING-TRACK: # Hand-written ref (Wave 1, verified against refs/tags/v1.0.0):
    # DISABLED-DURING-TRACK: ref:
      # DISABLED-DURING-TRACK: go-version: v1.0.0
      # DISABLED-DURING-TRACK: git-ref: v1.0.0-0-gad91dc4a3a642859730ff3d65929fce009bfdc23
      # DISABLED-DURING-TRACK: explicit: True

config:
  build-commands:
    # FSDK fscrypt/git-lfs pattern: replace the plugin-appended
    # vendor/modules.txt with the authoritative `go mod vendor` one.
    - |
      mv -vf modules.txt vendor/modules.txt
    - |
      ldflags="-X 'volcano.sh/volcano/pkg/version.GitSHA=%{volcano-git-sha}' -X 'volcano.sh/volcano/pkg/version.Version=%{volcano-version}'"
      for cmd in scheduler controller-manager webhook-manager; do
        go build -ldflags "${ldflags}" -o "vc-${cmd}" "./cmd/${cmd}"
      done

  install-commands:
    - |
      install -Dm755 -t "%{install-root}%{bindir}" \
        vc-scheduler vc-controller-manager vc-webhook-manager

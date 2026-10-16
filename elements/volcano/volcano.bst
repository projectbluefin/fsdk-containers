kind: manual
description: |
  Build volcano's control-plane binaries from source.

  Upstream: https://github.com/volcano-sh/volcano (CNCF batch scheduler).
  Ships vc-scheduler, vc-controller-manager and vc-webhook-manager.
  Node agents and vcctl are outside this image's scope.

  Dependencies are generated from `go mod vendor` at the pinned tag:
  199 go_module sources plus three immutable source archives for modules
  the pinned plugin cannot track. Each archive stages into vendor/<module>.
  The authoritative files/modules.txt records upstream replace directives
  and overwrites the plugin-appended manifest before the offline build.
  Regenerate the module set, refs, manifest and version stamps together.

  Builds have no network: GOROOT is explicit, GOPATH/GOCACHE live under the
  writable build root, and -mod=vendor forbids dependency downloads.
  CGO_ENABLED=0 follows upstream's static control-plane build. ldflags
  preserve upstream version/GitSHA stamps but omit the nonreproducible date.

build-depends:
  # FSDK 26.08 removed the shell from runtime-minimal; these commands
  # are shell scripts, so declare the interpreter explicitly.
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/go.bst

variables:
  strip-binaries: ""
  volcano-version: "v1.16.0"
  volcano-git-sha: "41f27d567fb5bdaf2cab01e1caaf48f7e266eefb"

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
    track: v1.16.0
    ref: v1.16.0-0-g41f27d567fb5bdaf2cab01e1caaf48f7e266eefb
  # Authoritative vendor manifest from `go mod vendor` at the pinned tag
  # (records replace directives the go_module plugin cannot).
  # Regenerate when bumping: clone tag, `go mod vendor`, copy
  # vendor/modules.txt here.
  - kind: local
    path: elements/volcano/files/modules.txt
  # Generated from vendor/modules.txt at v1.16.0. Resolve each version
  # to its source commit; sources absent from this manifest must be removed.
  - kind: go_module
    url: github:google/cel-spec.git
    module: cel.dev/expr
    ref:
      go-version: v0.25.1
      git-ref: v0.25.1-0-g7f3c4c513b42d471d0be9439bf5bde38f45f8404
      explicit: true
  # cyphar.com/go-pathrs v0.2.4: Four-field go-import metadata crashes go_module 2.3.1 tracking.
  - kind: tar
    url: github:cyphar/libpathrs/archive/dd498fd1504f9d9ef2da083f522bca6b7b0d3f6f.tar.gz
    ref: 9b1688f3e4ebc2ccb905c6b4f7038fcdbef83715d826e847a8965d710c6073b5
    base-dir: "*/go-pathrs"
    directory: vendor/cyphar.com/go-pathrs
  - kind: go_module
    url: github:AdaLogics/go-fuzz-headers.git
    module: github.com/AdaLogics/go-fuzz-headers
    ref:
      go-version: v0.0.0-20240806141605-e8a1dd7889d6
      git-ref: e8a1dd7889d65b8a6f02175e0d79d7c0557db7f9
      explicit: true
  - kind: go_module
    url: github:Azure/go-ansiterm.git
    module: github.com/Azure/go-ansiterm
    ref:
      go-version: v0.0.0-20250102033503-faa5f7b0171c
      git-ref: faa5f7b0171c46bb398a91b4a0c906324d3664cf
      explicit: true
  - kind: go_module
    url: github:JeffAshton/win_pdh.git
    module: github.com/JeffAshton/win_pdh
    ref:
      go-version: v0.0.0-20161109143554-76bb4ee9f0ab
      git-ref: 76bb4ee9f0ab50f77826f2a2ee7fb9d3880d6ec2
      explicit: true
  - kind: go_module
    url: github:MakeNowJust/heredoc.git
    module: github.com/MakeNowJust/heredoc
    ref:
      go-version: v1.0.0
      git-ref: v1.0.0-0-gbbd9af33722b79a933ef99c7c94833065e2d6c20
      explicit: true
  - kind: go_module
    url: github:Masterminds/semver.git
    module: github.com/Masterminds/semver/v3
    ref:
      go-version: v3.4.0
      git-ref: v3.4.0-0-g61fc460d28283a91c53be65c2e0f20b494ac8ad9
      explicit: true
  - kind: go_module
    url: github:Microsoft/go-winio.git
    module: github.com/Microsoft/go-winio
    ref:
      go-version: v0.6.2
      git-ref: v0.6.2-0-g3c9576c9346a1892dee136329e7e15309e82fb4f
      explicit: true
  - kind: go_module
    url: github:Microsoft/hnslib.git
    module: github.com/Microsoft/hnslib
    ref:
      go-version: v0.1.2
      git-ref: v0.1.2-0-g45ac02d25616f31bf4c4a661ca08c5e827cbde70
      explicit: true
  - kind: go_module
    url: github:NYTimes/gziphandler.git
    module: github.com/NYTimes/gziphandler
    ref:
      go-version: v1.1.1
      git-ref: v1.1.1-0-gdd0439581c7657cb652dfe5c71d7d48baf39541d
      explicit: true
  - kind: go_module
    url: github:agiledragon/gomonkey.git
    module: github.com/agiledragon/gomonkey/v2
    ref:
      go-version: v2.14.1
      git-ref: v2.14.1-0-gb18ce609446cfa34eb0b3d070c2e9d492606ed11
      explicit: true
  - kind: go_module
    url: github:antlr4-go/antlr.git
    module: github.com/antlr4-go/antlr/v4
    ref:
      go-version: v4.13.0
      git-ref: v4.13.0-0-g9549173c7ad83c2bf580a654ce0fe666fd7d2557
      explicit: true
  - kind: go_module
    url: github:beorn7/perks.git
    module: github.com/beorn7/perks
    ref:
      go-version: v1.0.1
      git-ref: v1.0.1-0-g37c8de3658fcb183f997c4e13e8337516ab753e6
      explicit: true
  - kind: go_module
    url: github:blang/semver.git
    module: github.com/blang/semver/v4
    ref:
      go-version: v4.0.0
      git-ref: v4.0.0-0-gaf3461a9cbcf1f3f5889d21b83f5ef63880c33a8
      explicit: true
  - kind: go_module
    url: github:cenkalti/backoff.git
    module: github.com/cenkalti/backoff/v5
    ref:
      go-version: v5.0.3
      git-ref: v5.0.3-0-g7cad66a637c4ffff09d0795608116ddcc7eb1769
      explicit: true
  - kind: go_module
    url: github:cespare/xxhash.git
    module: github.com/cespare/xxhash/v2
    ref:
      go-version: v2.3.0
      git-ref: v2.3.0-0-g998dce232f17418a7a5721ecf87ca714025a3243
      explicit: true
  - kind: go_module
    url: github:chai2010/gettext-go.git
    module: github.com/chai2010/gettext-go
    ref:
      go-version: v1.0.2
      git-ref: v1.0.2-0-g274d1753d015d0362761b6a1cc2a572e6a035913
      explicit: true
  - kind: go_module
    url: github:cilium/ebpf.git
    module: github.com/cilium/ebpf
    ref:
      go-version: v0.17.3
      git-ref: v0.17.3-0-g159dff1788cbfd31fcf301c9abaca55336596174
      explicit: true
  - kind: go_module
    url: github:container-storage-interface/spec.git
    module: github.com/container-storage-interface/spec
    ref:
      go-version: v1.9.0
      git-ref: v1.9.0-0-g80d53107c70981b9da8aaf9cd1c90249562b22f0
      explicit: true
  - kind: go_module
    url: github:containerd/containerd.git
    module: github.com/containerd/containerd/api
    ref:
      go-version: v1.10.0
      git-ref: api/v1.10.0-0-g8b34ce391bd114e080892cccfa956ef3807c207c
      explicit: true
      subdirectory: api
  - kind: go_module
    url: github:containerd/errdefs.git
    module: github.com/containerd/errdefs
    ref:
      go-version: v1.0.0
      git-ref: v1.0.0-0-g4817405e4a3caeb7aee9dac68ed55339c59cb635
      explicit: true
  - kind: go_module
    url: github:containerd/errdefs.git
    module: github.com/containerd/errdefs/pkg
    ref:
      go-version: v0.3.0
      git-ref: pkg/v0.3.0-0-g4817405e4a3caeb7aee9dac68ed55339c59cb635
      explicit: true
      subdirectory: pkg
  - kind: go_module
    url: github:containerd/log.git
    module: github.com/containerd/log
    ref:
      go-version: v0.1.0
      git-ref: v0.1.0-0-g0fc1e28871fdf2786e2cc51bbe4133db6547a199
      explicit: true
  - kind: go_module
    url: github:containerd/ttrpc.git
    module: github.com/containerd/ttrpc
    ref:
      go-version: v1.2.7
      git-ref: v1.2.7-0-g3b8c8b75577584e412043afb7b561193a4a47d2e
      explicit: true
  - kind: go_module
    url: github:containerd/typeurl.git
    module: github.com/containerd/typeurl/v2
    ref:
      go-version: v2.2.3
      git-ref: v2.2.3-0-g5b047adad57d172afa9654c019fe65bf0540cc4d
      explicit: true
  - kind: go_module
    url: github:containernetworking/cni.git
    module: github.com/containernetworking/cni
    ref:
      go-version: v1.3.0
      git-ref: v1.3.0-0-ga28faab92684aed3af64d5085733c34550ce9877
      explicit: true
  - kind: go_module
    url: github:containernetworking/plugins.git
    module: github.com/containernetworking/plugins
    ref:
      go-version: v1.1.1
      git-ref: v1.1.1-0-g4744ec27b89c083194e7df498de50f03a8a1d3ec
      explicit: true
  - kind: go_module
    url: github:coreos/go-semver.git
    module: github.com/coreos/go-semver
    ref:
      go-version: v0.3.1
      git-ref: v0.3.1-0-gc16f28124668daf02b2a32a431dec2f183977ffc
      explicit: true
  - kind: go_module
    url: github:coreos/go-systemd.git
    module: github.com/coreos/go-systemd/v22
    ref:
      go-version: v22.7.0
      git-ref: v22.7.0-0-g4dc4ee60b8394d431f19a3c599040ef758884a27
      explicit: true
  - kind: go_module
    url: github:cyphar/filepath-securejoin.git
    module: github.com/cyphar/filepath-securejoin
    ref:
      go-version: v0.6.1
      git-ref: v0.6.1-0-g9c4135bad38a4e2cda5220216000130d25b2e190
      explicit: true
  - kind: go_module
    url: github:davecgh/go-spew.git
    module: github.com/davecgh/go-spew
    ref:
      go-version: v1.1.2-0.20180830191138-d8f796af33cc
      git-ref: d8f796af33cc11cb798c1aaeb27a4ebc5099927d
      explicit: true
  - kind: go_module
    url: github:distribution/reference.git
    module: github.com/distribution/reference
    ref:
      go-version: v0.6.0
      git-ref: v0.6.0-0-gff14fafe2236e51c2894ac07d4bdfc778e96d682
      explicit: true
  - kind: go_module
    url: github:docker/go-units.git
    module: github.com/docker/go-units
    ref:
      go-version: v0.5.0
      git-ref: v0.5.0-0-ge682442797b36348f8e1f98defdbf32bac0b6c6f
      explicit: true
  - kind: go_module
    url: github:elastic/go-elasticsearch.git
    module: github.com/elastic/go-elasticsearch/v7
    ref:
      go-version: v7.17.10
      git-ref: v7.17.10-0-g559ea470985d31b06a20840257f8370b4c575c30
      explicit: true
  - kind: go_module
    url: github:emicklei/go-restful.git
    module: github.com/emicklei/go-restful/v3
    ref:
      go-version: v3.13.0
      git-ref: v3.13.0-0-g3fae6e4c6809ebc26315d163196ea7ab8e0685cb
      explicit: true
  - kind: go_module
    url: github:euank/go-kmsg-parser.git
    module: github.com/euank/go-kmsg-parser
    ref:
      go-version: v2.0.0+incompatible
      git-ref: v2.0.0-0-g5ba4d492e455a77d25dcf0d2c4acc9f2afebef4e
      explicit: true
  - kind: go_module
    url: github:evanphx/json-patch.git
    module: github.com/evanphx/json-patch/v5
    ref:
      go-version: v5.9.11
      git-ref: v5.9.11-0-g84a4bb100ade42a86fce2647c95a7dbcbf569cb2
      explicit: true
  - kind: go_module
    url: github:exponent-io/jsonpath.git
    module: github.com/exponent-io/jsonpath
    ref:
      go-version: v0.0.0-20210407135951-1de76d718b3f
      git-ref: 1de76d718b3f2694498041a6e578675bf52cee06
      explicit: true
  - kind: go_module
    url: github:fatih/camelcase.git
    module: github.com/fatih/camelcase
    ref:
      go-version: v1.0.0
      git-ref: v1.0.0-0-g44e46d280b43ec1531bb25252440e34f1b800b65
      explicit: true
  - kind: go_module
    url: github:felixge/httpsnoop.git
    module: github.com/felixge/httpsnoop
    ref:
      go-version: v1.0.4
      git-ref: v1.0.4-0-gc5817c27ec125409c069052fdd171023c353501c
      explicit: true
  - kind: go_module
    url: github:fsnotify/fsnotify.git
    module: github.com/fsnotify/fsnotify
    ref:
      go-version: v1.10.1
      git-ref: v1.10.1-0-g76b01a6e8f502187fecedea8b025e79e5a86085c
      explicit: true
  - kind: go_module
    url: github:fxamacker/cbor.git
    module: github.com/fxamacker/cbor/v2
    ref:
      go-version: v2.9.0
      git-ref: v2.9.0-0-gd29ad7351b55b1844387cf9306c4101658cc5256
      explicit: true
  - kind: go_module
    url: github:go-errors/errors.git
    module: github.com/go-errors/errors
    ref:
      go-version: v1.4.2
      git-ref: v1.4.2-0-g33d496f939bc762321a636d4035e15c302eb0b00
      explicit: true
  - kind: go_module
    url: github:go-logr/logr.git
    module: github.com/go-logr/logr
    ref:
      go-version: v1.4.4
      git-ref: v1.4.4-0-g96a9abaa56526dd5d51745e817732a2d61505fb7
      explicit: true
  - kind: go_module
    url: github:go-logr/stdr.git
    module: github.com/go-logr/stdr
    ref:
      go-version: v1.2.2
      git-ref: v1.2.2-0-g521af2addfa7c81c8a65d0e85ed34bb6bb6dc262
      explicit: true
  - kind: go_module
    url: github:go-openapi/jsonpointer.git
    module: github.com/go-openapi/jsonpointer
    ref:
      go-version: v0.22.5
      git-ref: v0.22.5-0-ge232aafbbdce6abbf028e4d6efebf845e1ff8148
      explicit: true
  - kind: go_module
    url: github:go-openapi/jsonreference.git
    module: github.com/go-openapi/jsonreference
    ref:
      go-version: v0.21.4
      git-ref: v0.21.4-0-ga073f3aad001f7cb05897a118dc11f8508be730d
      explicit: true
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag
    ref:
      go-version: v0.25.5
      git-ref: v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/cmdutils
    ref:
      go-version: v0.25.5
      git-ref: cmdutils/v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
      subdirectory: cmdutils
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/conv
    ref:
      go-version: v0.25.5
      git-ref: conv/v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
      subdirectory: conv
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/fileutils
    ref:
      go-version: v0.25.5
      git-ref: fileutils/v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
      subdirectory: fileutils
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/jsonname
    ref:
      go-version: v0.25.5
      git-ref: jsonname/v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
      subdirectory: jsonname
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/jsonutils
    ref:
      go-version: v0.25.5
      git-ref: jsonutils/v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
      subdirectory: jsonutils
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/loading
    ref:
      go-version: v0.25.5
      git-ref: loading/v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
      subdirectory: loading
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/mangling
    ref:
      go-version: v0.25.5
      git-ref: mangling/v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
      subdirectory: mangling
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/netutils
    ref:
      go-version: v0.25.5
      git-ref: netutils/v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
      subdirectory: netutils
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/stringutils
    ref:
      go-version: v0.25.5
      git-ref: stringutils/v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
      subdirectory: stringutils
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/typeutils
    ref:
      go-version: v0.25.5
      git-ref: typeutils/v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
      subdirectory: typeutils
  - kind: go_module
    url: github:go-openapi/swag.git
    module: github.com/go-openapi/swag/yamlutils
    ref:
      go-version: v0.25.5
      git-ref: yamlutils/v0.25.5-0-g86905ccd10f1987a41dd6988b6a6ec8c475bc449
      explicit: true
      subdirectory: yamlutils
  - kind: go_module
    url: github:go-task/slim-sprig.git
    module: github.com/go-task/slim-sprig/v3
    ref:
      go-version: v3.0.0
      git-ref: v3.0.0-0-gb05cce61fffa5c6dea6ac8b9a1f12b6e3fb7c894
      explicit: true
  - kind: go_module
    url: github:godbus/dbus.git
    module: github.com/godbus/dbus/v5
    ref:
      go-version: v5.2.2
      git-ref: v5.2.2-0-ga8ac15ba63645f02ffd57f4b443203279ab40b30
      explicit: true
  - kind: go_module
    url: github:gogo/protobuf.git
    module: github.com/gogo/protobuf
    ref:
      go-version: v1.3.2
      git-ref: v1.3.2-0-gb03c65ea87cdc3521ede29f62fe3ce239267c1bc
      explicit: true
  - kind: go_module
    url: github:golang/mock.git
    module: github.com/golang/mock
    ref:
      go-version: v1.6.0
      git-ref: v1.6.0-0-gaba2ff9a6844d5e3289e8472d3217d5b3090f083
      explicit: true
  - kind: go_module
    url: github:golang/protobuf.git
    module: github.com/golang/protobuf
    ref:
      go-version: v1.5.4
      git-ref: v1.5.4-0-g75de7c059e36b64f01d0dd234ff2fff404ec3374
      explicit: true
  - kind: go_module
    url: github:google/btree.git
    module: github.com/google/btree
    ref:
      go-version: v1.1.3
      git-ref: v1.1.3-0-gaeba20f7a1e1315badec4eca4fdc9f754f5f880a
      explicit: true
  - kind: go_module
    url: github:google/cadvisor.git
    module: github.com/google/cadvisor
    ref:
      go-version: v0.56.2
      git-ref: v0.56.2-0-g7cbdee9260c4292d5d27d00416ce8a7dc1dc12a0
      explicit: true
  - kind: go_module
    url: github:google/cel-go.git
    module: github.com/google/cel-go
    ref:
      go-version: v0.26.0
      git-ref: v0.26.0-0-gb023645243168e15bfe52522afccedfeb36ee023
      explicit: true
  - kind: go_module
    url: github:google/gnostic-models.git
    module: github.com/google/gnostic-models
    ref:
      go-version: v0.7.0
      git-ref: v0.7.0-0-g82b4ba06c153dcd30e1dbcf93601b3bee5cb3792
      explicit: true
  - kind: go_module
    url: github:google/go-cmp.git
    module: github.com/google/go-cmp
    ref:
      go-version: v0.7.0
      git-ref: v0.7.0-0-g9b12f366a942ebc7254abc7f32ca05068b455fb7
      explicit: true
  - kind: go_module
    url: github:google/pprof.git
    module: github.com/google/pprof
    ref:
      go-version: v0.0.0-20260402051712-545e8a4df936
      git-ref: 545e8a4df9364095d66e521b8f515f7af961e653
      explicit: true
  - kind: go_module
    url: github:google/shlex.git
    module: github.com/google/shlex
    ref:
      go-version: v0.0.0-20191202100458-e7afc7fbc510
      git-ref: e7afc7fbc51079733e9468cdfd1efcd7d196cd1d
      explicit: true
  - kind: go_module
    url: github:google/uuid.git
    module: github.com/google/uuid
    ref:
      go-version: v1.6.0
      git-ref: v1.6.0-0-g0f11ee6918f41a04c201eceeadf612a377bc7fbc
      explicit: true
  - kind: go_module
    url: github:gorilla/websocket.git
    module: github.com/gorilla/websocket
    ref:
      go-version: v1.5.4-0.20250319132907-e064f32e3674
      git-ref: e064f32e3674d9d79a8fd417b5bc06fa5c6cad8f
      explicit: true
  - kind: go_module
    url: github:grafana/regexp.git
    module: github.com/grafana/regexp
    ref:
      go-version: v0.0.0-20250905093917-f7b3be9d1853
      git-ref: f7b3be9d18538c56fb03caa6088db55404e784e8
      explicit: true
  - kind: go_module
    url: github:grpc-ecosystem/go-grpc-middleware.git
    module: github.com/grpc-ecosystem/go-grpc-middleware/providers/prometheus
    ref:
      go-version: v1.1.0
      git-ref: providers/prometheus/v1.1.0-0-g53040665d19bab33e444905822557433511bb981
      explicit: true
      subdirectory: providers/prometheus
  - kind: go_module
    url: github:grpc-ecosystem/go-grpc-middleware.git
    module: github.com/grpc-ecosystem/go-grpc-middleware/v2
    ref:
      go-version: v2.3.3
      git-ref: v2.3.3-0-g390bcef25adebe4b0c7dbb365230c0a856737afe
      explicit: true
  - kind: go_module
    url: github:grpc-ecosystem/grpc-gateway.git
    module: github.com/grpc-ecosystem/grpc-gateway/v2
    ref:
      go-version: v2.29.0
      git-ref: v2.29.0-0-gba9b55c1c15c84633be18c45463e123f31a5e999
      explicit: true
  - kind: go_module
    url: github:hashicorp/errwrap.git
    module: github.com/hashicorp/errwrap
    ref:
      go-version: v1.1.0
      git-ref: v1.1.0-0-g7b00e5db719c64d14dd0caaacbd13e76254d02c0
      explicit: true
  - kind: go_module
    url: github:hashicorp/go-multierror.git
    module: github.com/hashicorp/go-multierror
    ref:
      go-version: v1.1.1
      git-ref: v1.1.1-0-g9974e9ec57696378079ecc3accd3d6f29401b3a0
      explicit: true
  - kind: go_module
    url: github:imdario/mergo.git
    module: github.com/imdario/mergo
    ref:
      go-version: v0.3.16
      git-ref: v0.3.16-0-g14fe2b165b83359196f820886a2b24f2771729e9
      explicit: true
  - kind: go_module
    url: github:inconshreveable/mousetrap.git
    module: github.com/inconshreveable/mousetrap
    ref:
      go-version: v1.1.0
      git-ref: v1.1.0-0-g4e8053ee7ef85a6bd26368364a6d27f1641c1d21
      explicit: true
  - kind: go_module
    url: github:json-iterator/go.git
    module: github.com/json-iterator/go
    ref:
      go-version: v1.1.12
      git-ref: v1.1.12-0-g024077e996b048517130b21ea6bf12aa23055d3d
      explicit: true
  - kind: go_module
    url: github:klauspost/compress.git
    module: github.com/klauspost/compress
    ref:
      go-version: v1.19.2
      git-ref: v1.19.2-0-gc3b3439a48196b5082c63252bfb8633d0a2faad4
      explicit: true
  - kind: go_module
    url: github:kylelemons/godebug.git
    module: github.com/kylelemons/godebug
    ref:
      go-version: v1.1.0
      git-ref: v1.1.0-0-g9ff306d4fbead574800b66369df5b6144732d58e
      explicit: true
  - kind: go_module
    url: github:liggitt/tabwriter.git
    module: github.com/liggitt/tabwriter
    ref:
      go-version: v0.0.0-20181228230101-89fcab3d43de
      git-ref: 89fcab3d43de07060e4fd4c1547430ed57e87f24
      explicit: true
  # github.com/mistifyio/go-zfs v2.1.2-0.20190413222219-f784269be439+incompatible: go_module 2.3.1 cannot track +incompatible pseudo-versions.
  - kind: tar
    url: github:mistifyio/go-zfs/archive/f784269be439d704d3dfa1906f45dd848fed2beb.tar.gz
    ref: cc6eff48a242130a6b8fbf88ef301ae6a53564cb86d097c341c96a0b006449be
    base-dir: "*"
    directory: vendor/github.com/mistifyio/go-zfs
  - kind: go_module
    url: github:mitchellh/go-wordwrap.git
    module: github.com/mitchellh/go-wordwrap
    ref:
      go-version: v1.0.1
      git-ref: v1.0.1-0-gecf0936a077a4bd73a1cc2ac5c370f2b55618d62
      explicit: true
  - kind: go_module
    url: github:mitchellh/mapstructure.git
    module: github.com/mitchellh/mapstructure
    ref:
      go-version: v1.5.0
      git-ref: v1.5.0-0-gab69d8d93410fce4361f4912bb1ff88110a81311
      explicit: true
  - kind: go_module
    url: github:moby/spdystream.git
    module: github.com/moby/spdystream
    ref:
      go-version: v0.5.1
      git-ref: v0.5.1-0-gc59e5d73daa301bde452ea77545bdf51e32554a2
      explicit: true
  - kind: go_module
    url: github:moby/sys.git
    module: github.com/moby/sys/mountinfo
    ref:
      go-version: v0.7.2
      git-ref: mountinfo/v0.7.2-0-gcafbe42351600ca9b363e220722f66d96f6e71f4
      explicit: true
      subdirectory: mountinfo
  - kind: go_module
    url: github:moby/sys.git
    module: github.com/moby/sys/userns
    ref:
      go-version: v0.1.0
      git-ref: userns/v0.1.0-0-g54475191138bd297c627eb1a59e1e54b953957f1
      explicit: true
      subdirectory: userns
  - kind: go_module
    url: github:moby/term.git
    module: github.com/moby/term
    ref:
      go-version: v0.5.2
      git-ref: v0.5.2-0-g6c1b69fecbac2753dcaf18718a7e9f9093c3760d
      explicit: true
  - kind: go_module
    url: github:modern-go/concurrent.git
    module: github.com/modern-go/concurrent
    ref:
      go-version: v0.0.0-20180306012644-bacd9c7ef1dd
      git-ref: bacd9c7ef1dd9b15be4a9909b8ac7a4e313eec94
      explicit: true
  - kind: go_module
    url: github:modern-go/reflect2.git
    module: github.com/modern-go/reflect2
    ref:
      go-version: v1.0.3-0.20250322232337-35a7c28c31ee
      git-ref: 35a7c28c31ee079903db043180532306a621943a
      explicit: true
  - kind: go_module
    url: github:monochromegane/go-gitignore.git
    module: github.com/monochromegane/go-gitignore
    ref:
      go-version: v0.0.0-20200626010858-205db1a8cc00
      git-ref: 205db1a8cc001de79230472da52edde4974df734
      explicit: true
  - kind: go_module
    url: github:munnerz/goautoneg.git
    module: github.com/munnerz/goautoneg
    ref:
      go-version: v0.0.0-20191010083416-a7dc8b61c822
      git-ref: a7dc8b61c822528f973a5e4e7b272055c6fdb43e
      explicit: true
  - kind: go_module
    url: github:mxk/go-flowrate.git
    module: github.com/mxk/go-flowrate
    ref:
      go-version: v0.0.0-20140419014527-cca7078d478f
      git-ref: cca7078d478f8520f85629ad7c68962d31ed7682
      explicit: true
  - kind: go_module
    url: github:onsi/ginkgo.git
    module: github.com/onsi/ginkgo/v2
    ref:
      go-version: v2.32.0
      git-ref: v2.32.0-0-g9ff1646a26f77a4c0d33ddba3e6368c42c0e8842
      explicit: true
  - kind: go_module
    url: github:onsi/gomega.git
    module: github.com/onsi/gomega
    ref:
      go-version: v1.42.1
      git-ref: v1.42.1-0-gced6c1c9babf21968b76cfd49bfee4590339568a
      explicit: true
  - kind: go_module
    url: github:opencontainers/cgroups.git
    module: github.com/opencontainers/cgroups
    ref:
      go-version: v0.0.8
      git-ref: v0.0.8-0-g79cbc7ce7ce7dbc9f1059fb3f05cefe078111668
      explicit: true
  - kind: go_module
    url: github:opencontainers/go-digest.git
    module: github.com/opencontainers/go-digest
    ref:
      go-version: v1.0.0
      git-ref: v1.0.0-0-gea51bea511f75cfa3ef6098cc253c5c3609b037a
      explicit: true
  - kind: go_module
    url: github:opencontainers/image-spec.git
    module: github.com/opencontainers/image-spec
    ref:
      go-version: v1.1.1
      git-ref: v1.1.1-0-g147f9c13cedb47a0c4d9a11a222961073d585877
      explicit: true
  - kind: go_module
    url: github:opencontainers/runtime-spec.git
    module: github.com/opencontainers/runtime-spec
    ref:
      go-version: v1.3.0
      git-ref: v1.3.0-0-g92249139eea7161e13745abd4cb6d0ea02a3227a
      explicit: true
  - kind: go_module
    url: github:opencontainers/selinux.git
    module: github.com/opencontainers/selinux
    ref:
      go-version: v1.13.1
      git-ref: v1.13.1-0-g5647f06491288afa5ea45747896b359f51f7c509
      explicit: true
  - kind: go_module
    url: github:peterbourgon/diskv.git
    module: github.com/peterbourgon/diskv
    ref:
      go-version: v2.0.1+incompatible
      git-ref: v2.0.1-0-g5f041e8faa004a95c88a202771f4cc3e991971e6
      explicit: true
  - kind: go_module
    url: github:pkg/errors.git
    module: github.com/pkg/errors
    ref:
      go-version: v0.9.1
      git-ref: v0.9.1-0-g614d223910a179a466c1767a985424175c39b465
      explicit: true
  - kind: go_module
    url: github:pmezard/go-difflib.git
    module: github.com/pmezard/go-difflib
    ref:
      go-version: v1.0.1-0.20181226105442-5d4384ee4fb2
      git-ref: 5d4384ee4fb2527b0a1256a821ebfc92f91efefc
      explicit: true
  - kind: go_module
    url: github:prometheus/client_golang.git
    module: github.com/prometheus/client_golang
    ref:
      go-version: v1.23.2
      git-ref: v1.23.2-0-g8179a560819f2c64ef6ade70e6ae4c73aecaca3c
      explicit: true
  - kind: go_module
    url: github:prometheus/client_model.git
    module: github.com/prometheus/client_model
    ref:
      go-version: v0.6.2
      git-ref: v0.6.2-0-geb136e513d419e0c31ad750922f0a6f7675c2dee
      explicit: true
  - kind: go_module
    url: github:prometheus/common.git
    module: github.com/prometheus/common
    ref:
      go-version: v0.70.0
      git-ref: v0.70.0-0-g5eff7a827920b6f175ea02b222f7c827a0fe80ad
      explicit: true
  - kind: go_module
    url: github:prometheus/procfs.git
    module: github.com/prometheus/procfs
    ref:
      go-version: v0.21.0
      git-ref: v0.21.0-0-g95dd8b801f0653ff7c110bcdbc354075e60d62e8
      explicit: true
  - kind: go_module
    url: github:prometheus/prometheus.git
    module: github.com/prometheus/prometheus
    ref:
      go-version: v0.311.3
      git-ref: v0.311.3-0-geb173f5256d4022afba1e9bc3d19740a76859fae
      explicit: true
  - kind: go_module
    url: github:robfig/cron.git
    module: github.com/robfig/cron/v3
    ref:
      go-version: v3.0.1
      git-ref: v3.0.1-0-gccba498c397bb90a9c84945bbb0f7af2d72b6309
      explicit: true
  - kind: go_module
    url: github:russross/blackfriday.git
    module: github.com/russross/blackfriday/v2
    ref:
      go-version: v2.1.0
      git-ref: v2.1.0-0-g4c9bf9512682b995722660a4196c0013228e2049
      explicit: true
  - kind: go_module
    url: github:sirupsen/logrus.git
    module: github.com/sirupsen/logrus
    ref:
      go-version: v1.9.4
      git-ref: v1.9.4-0-gb61f268f75b6ff134a62cd62aee1095fa12e8d2e
      explicit: true
  - kind: go_module
    url: github:spf13/cobra.git
    module: github.com/spf13/cobra
    ref:
      go-version: v1.10.2
      git-ref: v1.10.2-0-g88b30ab89da2d0d0abb153818746c5a2d30eccec
      explicit: true
  - kind: go_module
    url: github:spf13/pflag.git
    module: github.com/spf13/pflag
    ref:
      go-version: v1.0.10
      git-ref: v1.0.10-0-g0491e5702ad2bb108bc519a5221bcc0f52aa9564
      explicit: true
  - kind: go_module
    url: github:stoewer/go-strcase.git
    module: github.com/stoewer/go-strcase
    ref:
      go-version: v1.3.0
      git-ref: v1.3.0-0-g6c4ce445f323378b0865757ffd2c50d8bb2737f8
      explicit: true
  - kind: go_module
    url: github:stretchr/testify.git
    module: github.com/stretchr/testify
    ref:
      go-version: v1.11.1
      git-ref: v1.11.1-0-g2a57335dc9cd6833daa820bc94d9b40c26a7917d
      explicit: true
  - kind: go_module
    url: github:vishvananda/netlink.git
    module: github.com/vishvananda/netlink
    ref:
      go-version: v1.3.1
      git-ref: v1.3.1-0-g17daef607c6442d47b0565343cf8a69f985a4cb7
      explicit: true
  - kind: go_module
    url: github:vishvananda/netns.git
    module: github.com/vishvananda/netns
    ref:
      go-version: v0.0.5
      git-ref: v0.0.5-0-g4c46424d73b556b3ea4bc5a7cec9e7376dcb2a73
      explicit: true
  - kind: go_module
    url: github:x448/float16.git
    module: github.com/x448/float16
    ref:
      go-version: v0.8.4
      git-ref: v0.8.4-0-gcb9afec31f2649663ebb64da5c6c32c3d365c3ca
      explicit: true
  - kind: go_module
    url: github:xlab/treeprint.git
    module: github.com/xlab/treeprint
    ref:
      go-version: v1.2.0
      git-ref: v1.2.0-0-g044005a3b405f660f109e066d9f589755835c2ea
      explicit: true
  - kind: go_module
    url: github:etcd-io/etcd.git
    module: go.etcd.io/etcd/api/v3
    ref:
      go-version: v3.6.14
      git-ref: api/v3.6.14-0-gfc04cf702b0a46c2fd85547a2be05705b100a496
      explicit: true
      subdirectory: api
  - kind: go_module
    url: github:etcd-io/etcd.git
    module: go.etcd.io/etcd/client/pkg/v3
    ref:
      go-version: v3.6.14
      git-ref: client/pkg/v3.6.14-0-gfc04cf702b0a46c2fd85547a2be05705b100a496
      explicit: true
      subdirectory: client/pkg
  - kind: go_module
    url: github:etcd-io/etcd.git
    module: go.etcd.io/etcd/client/v3
    ref:
      go-version: v3.6.14
      git-ref: client/v3.6.14-0-gfc04cf702b0a46c2fd85547a2be05705b100a496
      explicit: true
      subdirectory: client
  - kind: go_module
    url: github:etcd-io/etcd.git
    module: go.etcd.io/etcd/server/v3
    ref:
      go-version: v3.6.14
      git-ref: server/v3.6.14-0-gfc04cf702b0a46c2fd85547a2be05705b100a496
      explicit: true
      subdirectory: server
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go-instrumentation.git
    module: go.opentelemetry.io/auto/sdk
    ref:
      go-version: v1.2.1
      git-ref: sdk/v1.2.1-0-g715f58ce2f17e2176b8e53b871e47531a259cc1d
      explicit: true
      subdirectory: sdk
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go-contrib.git
    module: go.opentelemetry.io/contrib/instrumentation/github.com/emicklei/go-restful/otelrestful
    ref:
      go-version: v0.65.0
      git-ref: instrumentation/github.com/emicklei/go-restful/otelrestful/v0.65.0-0-ga89d958e7a2575cf539ffca09657cfd90821d6e4
      explicit: true
      subdirectory: instrumentation/github.com/emicklei/go-restful/otelrestful
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go-contrib.git
    module: go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc
    ref:
      go-version: v0.65.0
      git-ref: instrumentation/google.golang.org/grpc/otelgrpc/v0.65.0-0-ga89d958e7a2575cf539ffca09657cfd90821d6e4
      explicit: true
      subdirectory: instrumentation/google.golang.org/grpc/otelgrpc
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go-contrib.git
    module: go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
    ref:
      go-version: v0.67.0
      git-ref: instrumentation/net/http/otelhttp/v0.67.0-0-gd8dabf67361a4619c353ad0637432f3d0d16ba63
      explicit: true
      subdirectory: instrumentation/net/http/otelhttp
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel
    ref:
      go-version: v1.45.0
      git-ref: v1.45.0-0-g93a693edeed0e07ce5ebd1dfe67af42d1e2055d8
      explicit: true
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel/exporters/otlp/otlptrace
    ref:
      go-version: v1.45.0
      git-ref: exporters/otlp/otlptrace/v1.45.0-0-g93a693edeed0e07ce5ebd1dfe67af42d1e2055d8
      explicit: true
      subdirectory: exporters/otlp/otlptrace
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc
    ref:
      go-version: v1.42.0
      git-ref: exporters/otlp/otlptrace/otlptracegrpc/v1.42.0-0-ga3941ff595235e952774f0a581c7655bec93b0ab
      explicit: true
      subdirectory: exporters/otlp/otlptrace/otlptracegrpc
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel/metric
    ref:
      go-version: v1.45.0
      git-ref: metric/v1.45.0-0-g93a693edeed0e07ce5ebd1dfe67af42d1e2055d8
      explicit: true
      subdirectory: metric
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel/sdk
    ref:
      go-version: v1.45.0
      git-ref: sdk/v1.45.0-0-g93a693edeed0e07ce5ebd1dfe67af42d1e2055d8
      explicit: true
      subdirectory: sdk
  - kind: go_module
    url: github:open-telemetry/opentelemetry-go.git
    module: go.opentelemetry.io/otel/trace
    ref:
      go-version: v1.45.0
      git-ref: trace/v1.45.0-0-g93a693edeed0e07ce5ebd1dfe67af42d1e2055d8
      explicit: true
      subdirectory: trace
  - kind: go_module
    url: github:open-telemetry/opentelemetry-proto-go.git
    module: go.opentelemetry.io/proto/otlp
    ref:
      go-version: v1.11.0
      git-ref: otlp/v1.11.0-0-gbc625d6e040020737ab65c675c87e03bc841fd60
      explicit: true
      subdirectory: otlp
  - kind: go_module
    url: github:uber-go/automaxprocs.git
    module: go.uber.org/automaxprocs
    ref:
      go-version: v1.6.0
      git-ref: v1.6.0-0-g1ea14c35ce47a73089b824e504d1c92eeb61a5a6
      explicit: true
  - kind: go_module
    url: github:uber-go/multierr.git
    module: go.uber.org/multierr
    ref:
      go-version: v1.11.0
      git-ref: v1.11.0-0-gde75ae527b39a27afcb50a84427ec7b84021d5f4
      explicit: true
  - kind: go_module
    url: github:uber-go/zap.git
    module: go.uber.org/zap
    ref:
      go-version: v1.27.1
      git-ref: v1.27.1-0-g7b755a3910491932656b01f2013b8bf41e74d4e8
      explicit: true
  - kind: go_module
    url: github:yaml/go-yaml.git
    module: go.yaml.in/yaml/v2
    ref:
      go-version: v2.4.4
      git-ref: v2.4.4-0-g43b627a9da72517e91dbcf07cd10dfd6618423d8
      explicit: true
  - kind: go_module
    url: github:yaml/go-yaml.git
    module: go.yaml.in/yaml/v3
    ref:
      go-version: v3.0.4
      git-ref: v3.0.4-0-gc3552c15f996075a7634df5159d9161c67bf3d76
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/crypto
    module: golang.org/x/crypto
    ref:
      go-version: v0.56.0
      git-ref: v0.56.0-0-g86efde54dc7069251a8b007026c500d28e4239ce
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/exp
    module: golang.org/x/exp
    ref:
      go-version: v0.0.0-20260218203240-3dfff04db8fa
      git-ref: 3dfff04db8fa6b6338ec60a0317f99db30637e41
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/mod
    module: golang.org/x/mod
    ref:
      go-version: v0.40.0
      git-ref: v0.40.0-0-gd3398d06de5fa5c71083d3d1c26f2cda73508e0f
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/net
    module: golang.org/x/net
    ref:
      go-version: v0.58.0
      git-ref: v0.58.0-0-gacc78e0d2b2c855c0c4fbdcfe5f42a9e3d0f9778
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/oauth2
    module: golang.org/x/oauth2
    ref:
      go-version: v0.36.0
      git-ref: v0.36.0-0-g4d954e69a88d9e1ccb8439f8d5b6cbef230c4ef9
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/sync
    module: golang.org/x/sync
    ref:
      go-version: v0.22.0
      git-ref: v0.22.0-0-g1eb64d4bc0cde6da1bb8ebc7f178bb577508e5d0
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/sys
    module: golang.org/x/sys
    ref:
      go-version: v0.47.0
      git-ref: v0.47.0-0-g9e7e939dcafac07e8ab4cffa6e5fc74908413f00
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/term
    module: golang.org/x/term
    ref:
      go-version: v0.45.0
      git-ref: v0.45.0-0-g9f69229da31ca6a34b522f59dbe07cad5ea21587
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/text
    module: golang.org/x/text
    ref:
      go-version: v0.41.0
      git-ref: v0.41.0-0-gacdba6655fd45cdb5ab73c9d6a8981333bd65a39
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/time
    module: golang.org/x/time
    ref:
      go-version: v0.15.0
      git-ref: v0.15.0-0-g812b343c8714c317b0dad633efa6d103e554c006
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/tools
    module: golang.org/x/tools
    ref:
      go-version: v0.49.0
      git-ref: v0.49.0-0-g18332fec72972efbb8ab9881984fec2d8cfc2b58
      explicit: true
  - kind: go_module
    url: github:googleapis/go-genproto.git
    module: google.golang.org/genproto/googleapis/api
    ref:
      go-version: v0.0.0-20260720211330-0afa2a65878a
      git-ref: 0afa2a65878ac60e55854f304541430c0b7368f1
      explicit: true
      subdirectory: googleapis/api
  - kind: go_module
    url: github:googleapis/go-genproto.git
    module: google.golang.org/genproto/googleapis/rpc
    ref:
      go-version: v0.0.0-20260720211330-0afa2a65878a
      git-ref: 0afa2a65878ac60e55854f304541430c0b7368f1
      explicit: true
      subdirectory: googleapis/rpc
  - kind: go_module
    url: github:grpc/grpc-go.git
    module: google.golang.org/grpc
    ref:
      go-version: v1.82.1
      git-ref: v1.82.1-0-gebd8f06a09426fbece97157c95c3917abff28f4e
      explicit: true
  - kind: go_module
    url: https://go.googlesource.com/protobuf
    module: google.golang.org/protobuf
    ref:
      go-version: v1.36.12-0.20260120151049-f2248ac996af
      git-ref: f2248ac996afc39b3df0777cdcc269f6ade50b07
      explicit: true
  - kind: go_module
    url: https://gopkg.in/evanphx/json-patch.v4
    module: gopkg.in/evanphx/json-patch.v4
    ref:
      go-version: v4.13.0
      git-ref: v4.13.0-0-g84a4bb100ade42a86fce2647c95a7dbcbf569cb2
      explicit: true
  - kind: go_module
    url: https://gopkg.in/inf.v0
    module: gopkg.in/inf.v0
    ref:
      go-version: v0.9.1
      git-ref: v0.9.1-0-gd2d2541c53f18d2a059457998ce2876cc8e67cbf
      explicit: true
  - kind: go_module
    url: https://gopkg.in/natefinch/lumberjack.v2
    module: gopkg.in/natefinch/lumberjack.v2
    ref:
      go-version: v2.2.1
      git-ref: v2.2.1-0-g4cb27fcfbb0f35cb48c542c5ea80b7c1d18933d0
      explicit: true
  - kind: go_module
    url: https://gopkg.in/yaml.v2
    module: gopkg.in/yaml.v2
    ref:
      go-version: v2.4.0
      git-ref: v2.4.0-0-g7649d4548cb53a614db133b2a8ac1f31859dda8c
      explicit: true
  - kind: go_module
    url: https://gopkg.in/yaml.v3
    module: gopkg.in/yaml.v3
    ref:
      go-version: v3.0.1
      git-ref: v3.0.1-0-gf6f7691b1fdeb513f56608cd2c32c51f8194bf51
      explicit: true
  - kind: go_module
    url: github:kubernetes/api.git
    module: k8s.io/api
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g25001c854943b552769cd32eacd0bef7467c0eea
      explicit: true
  - kind: go_module
    url: github:kubernetes/apiextensions-apiserver.git
    module: k8s.io/apiextensions-apiserver
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g5b822b18256d51149c9b9f7224d2a91c283119a5
      explicit: true
  - kind: go_module
    url: github:kubernetes/apimachinery.git
    module: k8s.io/apimachinery
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g7af103a2a439106791220493349f8d13bc0a1efd
      explicit: true
  - kind: go_module
    url: github:kubernetes/apiserver.git
    module: k8s.io/apiserver
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-gf5c87c5976dc9966aa63ea0021d5baf9ceef2efc
      explicit: true
  - kind: go_module
    url: github:kubernetes/cli-runtime.git
    module: k8s.io/cli-runtime
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g62458b59d11d63722e3c548f014db1a24f35e011
      explicit: true
  - kind: go_module
    url: github:kubernetes/client-go.git
    module: k8s.io/client-go
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g55ef15a9fb552182b78f7b1d0d09d618632dfe7f
      explicit: true
  - kind: go_module
    url: github:kubernetes/cloud-provider.git
    module: k8s.io/cloud-provider
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g557a943ec4335135ad3f4072cb4cb464dfae3bf6
      explicit: true
  - kind: go_module
    url: github:kubernetes/code-generator.git
    module: k8s.io/code-generator
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g5f4d453e014b7a9f57fe4d6ea2ffbad3943f3d14
      explicit: true
  - kind: go_module
    url: github:kubernetes/component-base.git
    module: k8s.io/component-base
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g8b552405353e5e30c353608fb8711d959d5b45f7
      explicit: true
  - kind: go_module
    url: github:kubernetes/component-helpers.git
    module: k8s.io/component-helpers
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g58f41a038a788a08304687af09485e437d8c0e51
      explicit: true
  - kind: go_module
    url: github:kubernetes/controller-manager.git
    module: k8s.io/controller-manager
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g2edff568f5e8ccf318588ffe8afd86453b7c9bda
      explicit: true
  - kind: go_module
    url: github:kubernetes/cri-api.git
    module: k8s.io/cri-api
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-gb569fd7e8091a45af0adc2938152be8124f2948d
      explicit: true
  - kind: go_module
    url: github:kubernetes/cri-client.git
    module: k8s.io/cri-client
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-ga21d8707e974de1ae29b5d8df4aa7368acb5ab5a
      explicit: true
  - kind: go_module
    url: github:kubernetes/cri-streaming.git
    module: k8s.io/cri-streaming
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g23826f807fec39b80751482cac07f5924e94607b
      explicit: true
  - kind: go_module
    url: github:kubernetes/csi-translation-lib.git
    module: k8s.io/csi-translation-lib
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g73adc08eb7f287a65d2fd39a6b796c8965931521
      explicit: true
  - kind: go_module
    url: github:kubernetes/dynamic-resource-allocation.git
    module: k8s.io/dynamic-resource-allocation
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g3bc82de599c4d60508edb9ef2d6650a11bf2548f
      explicit: true
  - kind: go_module
    url: github:kubernetes/gengo.git
    module: k8s.io/gengo/v2
    ref:
      go-version: v2.0.0-20250922181213-ec3ebc5fd46b
      git-ref: ec3ebc5fd46b84f44dfb135e9684c6567791dd8e
      explicit: true
  - kind: go_module
    url: github:kubernetes/klog.git
    module: k8s.io/klog/v2
    ref:
      go-version: v2.140.0
      git-ref: ef4b370a5578b77a401416e4d12f5900cc8850cb
      explicit: true
  - kind: go_module
    url: github:kubernetes/kms.git
    module: k8s.io/kms
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g940bf08874463ab61d5b6b447e6d606c4b362af4
      explicit: true
  - kind: go_module
    url: github:kubernetes/kube-openapi.git
    module: k8s.io/kube-openapi
    ref:
      go-version: v0.0.0-20260317180543-43fb72c5454a
      git-ref: 43fb72c5454a03ed83388cf20c070499ee359af8
      explicit: true
  - kind: go_module
    url: github:kubernetes/kube-scheduler.git
    module: k8s.io/kube-scheduler
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g141ccb1cf6da1eedc6fc2a7dd14265bc8bd0f1fa
      explicit: true
  - kind: go_module
    url: github:kubernetes/kubectl.git
    module: k8s.io/kubectl
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g01cb18cdbab1c5d4fd4dd0fc7005789d35989d22
      explicit: true
  - kind: go_module
    url: github:kubernetes/kubelet.git
    module: k8s.io/kubelet
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-gbd341c4c2e01c0d7a52af4e93bea3f6bf6a31f76
      explicit: true
  - kind: go_module
    url: github:kubernetes/kubernetes.git
    module: k8s.io/kubernetes
    ref:
      go-version: v1.36.1
      git-ref: v1.36.1-0-g756939600b9a7180fc2df6550a4585b638875e67
      explicit: true
  - kind: go_module
    url: github:kubernetes/metrics.git
    module: k8s.io/metrics
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-gc1f09754efe900985ad4225c780c9618c1037c04
      explicit: true
  - kind: go_module
    url: github:kubernetes/mount-utils.git
    module: k8s.io/mount-utils
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-g2f116ccea98ebd0e2f68d625935c60d393e9b46d
      explicit: true
  - kind: go_module
    url: github:kubernetes/pod-security-admission.git
    module: k8s.io/pod-security-admission
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-gae095a503da5e8ff06330f2b59c2c67012c26397
      explicit: true
  - kind: go_module
    url: github:kubernetes/streaming.git
    module: k8s.io/streaming
    ref:
      go-version: v0.36.1
      git-ref: v0.36.1-0-gfbcf184e52bfd8a40d46311b494493c287fd6d05
      explicit: true
  - kind: go_module
    url: github:kubernetes/utils.git
    module: k8s.io/utils
    ref:
      go-version: v0.0.0-20260210185600-b8788abfbbc2
      git-ref: b8788abfbbc27cab6c8732274b5c2ae213868854
      explicit: true
  - kind: go_module
    url: github:kubernetes-sigs/apiserver-network-proxy.git
    module: sigs.k8s.io/apiserver-network-proxy/konnectivity-client
    ref:
      go-version: v0.34.0
      git-ref: konnectivity-client/v0.34.0-0-g7c8afbabc7ed3e01f2ad57db744139822366721f
      explicit: true
      subdirectory: konnectivity-client
  - kind: go_module
    url: github:kubernetes-sigs/controller-runtime.git
    module: sigs.k8s.io/controller-runtime
    ref:
      go-version: v0.24.1
      git-ref: v0.24.1-0-g3be3f1bf2b2fcc6b5c9510d55c6a9972294653d0
      explicit: true
  - kind: go_module
    url: github:kubernetes-sigs/e2e-framework.git
    module: sigs.k8s.io/e2e-framework
    ref:
      go-version: v0.7.0
      git-ref: v0.7.0-0-g7d89e243fe3318615cfa4cebd880b22c6f13fabd
      explicit: true
  - kind: go_module
    url: github:kubernetes-sigs/json.git
    module: sigs.k8s.io/json
    ref:
      go-version: v0.0.0-20250730193827-2d320260d730
      git-ref: 2d320260d730f3842fef7b08d9a807bdbc617824
      explicit: true
  - kind: go_module
    url: github:kubernetes-sigs/kustomize.git
    module: sigs.k8s.io/kustomize/api
    ref:
      go-version: v0.21.1
      git-ref: api/v0.21.1-0-g401be204e1c0e91c8122f7cdab5564e38a66cae0
      explicit: true
      subdirectory: api
  - kind: go_module
    url: github:kubernetes-sigs/kustomize.git
    module: sigs.k8s.io/kustomize/kyaml
    ref:
      go-version: v0.21.1
      git-ref: kyaml/v0.21.1-0-g798d339d1049c82ba4a286f33f7165ecca1dfe6f
      explicit: true
      subdirectory: kyaml
  - kind: go_module
    url: github:kubernetes-sigs/randfill.git
    module: sigs.k8s.io/randfill
    ref:
      go-version: v1.0.0
      git-ref: v1.0.0-0-g1b6128de8ceabf6d20c4d81d770bf439c1494960
      explicit: true
  - kind: go_module
    url: github:kubernetes-sigs/structured-merge-diff.git
    module: sigs.k8s.io/structured-merge-diff/v6
    ref:
      go-version: v6.3.2
      git-ref: v6.3.2-0-gd9cc6641c48292946e838bfc3b9bf7c297526757
      explicit: true
  - kind: go_module
    url: github:kubernetes-sigs/yaml.git
    module: sigs.k8s.io/yaml
    ref:
      go-version: v1.6.0
      git-ref: v1.6.0-0-g048d724aca2d37ddb5b03c90b5b4550a3a48766d
      explicit: true
  # stathat.com/c/consistent v1.0.0: The vanity domain is defunct; pin the historical source repository.
  - kind: tar
    url: github:stathat/consistent/archive/ad91dc4a3a642859730ff3d65929fce009bfdc23.tar.gz
    ref: f3931f64e94a8a4c539c638e5a597558458c11f98552639629cff9531c2cb11c
    base-dir: "*"
    directory: vendor/stathat.com/c/consistent

config:
  build-commands:
    # FSDK fscrypt/git-lfs pattern: replace the plugin-appended
    # vendor/modules.txt with the authoritative `go mod vendor` one.
    - |
      mv -vf modules.txt vendor/modules.txt
      # A local go.mod replacement is part of the main source, not a
      # go_module download, but -mod=vendor still requires its vendor tree.
      mkdir -p vendor/volcano.sh
      cp -a staging/src/volcano.sh/apis vendor/volcano.sh/apis
    - |
      ldflags="-X 'volcano.sh/volcano/pkg/version.GitSHA=%{volcano-git-sha}' -X 'volcano.sh/volcano/pkg/version.Version=%{volcano-version}'"
      for cmd in scheduler controller-manager webhook-manager; do
        go build -ldflags "${ldflags}" -o "vc-${cmd}" "./cmd/${cmd}"
      done

  install-commands:
    - |
      install -Dm755 -t "%{install-root}%{bindir}" \
        vc-scheduler vc-controller-manager vc-webhook-manager

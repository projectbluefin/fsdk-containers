kind: manual
description: |
  Build the donate-clanker guest worker from the pinned VM bootstrap source.
  The source is pinned to the published donate-clanker main commit.

sources:
  - kind: git_repo
    url: github:projectbluefin/donate-clanker.git
    ref: 5155b0bbdba0262b0ed1d948acf8d2e26b8205ce
    directory: donate-clanker
  - kind: git_repo
    url: github:gorilla/websocket.git
    ref: ce903f6d1d961af3a8602f2842c8b1c3fca58c4d
    directory: gorilla-websocket

build-depends:
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:components/go.bst

variables:
  strip-binaries: ""

config:
  build-commands:
    - |
      cd donate-clanker
      go mod edit -replace=github.com/gorilla/websocket=../gorilla-websocket
      GOPROXY=off GOSUMDB=off CGO_ENABLED=0 \
        go build -mod=mod -trimpath -buildvcs=false \
        -ldflags='-s -w' \
        -o "%{install-root}/usr/libexec/donate-clanker-worker" \
        ./cmd/contributor

---
name: go-module-source
version: "1.1"
last_updated: 2026-08-24
id: go-module-source
one_line_purpose: Build Go projects from source with the go_module plugin — vendored deps, no network at build time.
entry_point: docs/skills/go-module-source.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: [remote-execution, track-upstream-versions]
tags: [go, go_module, vendoring, source-plugin, provenance, catalog]
description: "The proven recipe for the buildstream-plugins-community go_module source plugin: YAML shape, bst source track workflow, the modules.txt/replace trap, RE-grid env (GOROOT triplet), and vanity-import workarounds. Use when adding any Go-based catalog element."
metadata:
  type: procedure
  context7-sources:
    - /apache/buildstream
---

# Building Go projects with the `go_module` source plugin

Use when adding a Go-based element that must build from source (the catalog
provenance rule — never import prebuilt binaries).

Proven end-to-end 2026-08-09 (issue #113, Wave 1): plugin enabled in
`project.conf`, tracked and built on the ghost BuildBarn grid with
`elements/go-md2man/go-md2man.bst` (1 module) and stress-tested with
`elements/volcano/volcano.bst` (235 modules, 37 replace directives).

## Plugin registration (already done)

`project.conf` junctions `plugins/buildstream-plugins-community.bst` (2.3.1)
and lists `go_module` under `sources:`. Without that line every element using
the plugin fails at load with
`No source plugin registered for kind 'go_module'`.

## Element shape

One `git_repo` source for the project itself, then **one `go_module` source
per vendored module** (the plugin does no transitive resolution — list every
module from `go mod vendor` output, i.e. every module with a non-`/go.mod`
hash line in `go.sum`):

```yaml
sources:
  - kind: git_repo
    url: github:cpuguy83/go-md2man.git
    # renovate: datasource=github-tags depName=cpuguy83/go-md2man
    track: v2.0.7
    ref: v2.0.7-0-g061b6c7cbecd6752049221aa15b7a05160796698
  - kind: go_module
    url: github:russross/blackfriday.git
    module: github.com/russross/blackfriday/v2
    ref:                      # filled by 'bst source track' — never hand-guess
      go-version: v2.1.0      # go version string from go.sum
      git-ref: v2.1.0-0-g4c9bf9512682b995722660a4196c0013228e2049  # git-describe
      explicit: True          # module appears (as text) in go.mod
      subdirectory: ...       # optional: module lives in a repo subdir
```

## `bst source track` fills every `ref:` — the intended workflow

`just bst source track <element>` tracks sources in order: the `git_repo`
first, then each `go_module` reads **`go.sum` and `go.mod` from the staged
previous sources** (the plugin declares
`BST_REQUIRES_PREVIOUS_SOURCES_TRACK = True`), finds its module's version
line, and resolves it to a git-describe ref:

- pseudo-versions (`v0.0.0-20240101-deadbeef1234`) → commit sha resolved
  directly;
- plain versions → tag lookup (`<subdirectory>/<version>` or `<version>`)
  on the module's git remote.

Traps observed:

- **track() re-runs on sources that already have refs.** It always
  re-resolves. A source whose `track()` crashes (see vanity traps below)
  must be **commented out before tracking**, or the whole element's track
  fails and no refs are saved.
- **`explicit` is a dumb substring match**: `self.module in go.mod_text`.
  Modules listed with `// indirect` still come out `explicit: True`. For
  `go >= 1.14` go.mod directives that mismatch makes go's vendor
  consistency check fail (`marked as explicit in vendor/modules.txt, but
  not explicitly required in go.mod`) *if* you rely on the
  plugin-generated modules.txt — another reason to ship your own (next
  section).
- `bst source track` rewrites the element file with BuildStream's
  round-trip YAML: hand-tuned indentation drifts, comments survive.
  Review the diff after tracking.
- `bst source track` also advances any earlier `git_repo` source with a
  moving `track:` ref. If later local sources pin root-level `go.mod` and
  `go.sum` anchors for a subdirectory module, that can silently produce a
  mixed element: a new project commit with dependency refs derived from the
  old anchors. Either refresh the anchors, generated `modules.txt`, and build
  metadata as one version bump, or restore the original project `ref:` after
  tracking. `kubestellar-hive/hive-bin.bst` is the latter case.

## The `vendor/modules.txt` trap — ship your own for anything non-trivial

On stage, each `go_module` source links its module tree into
`vendor/<module>/` and **appends** to `vendor/modules.txt`. That generated
file is NOT trustworthy:

1. **No `replace` directives are recorded.** go's vendor consistency check
   fails when go.mod has replaces (volcano has 37).
2. For non-`explicit` modules the plugin writes `# <module>` **without a
   version**, which the consistency check rejects (go ≥ 1.14 go.mod
   directive).
3. Package lines are the whole module tree (unpruned), not what
   `go mod vendor` would write — harmless for the check, but don't confuse
   it with real vendor output.

FSDK's production pattern (`fscrypt.bst`, `git-lfs.bst`): stage the real
`go mod vendor`-generated `modules.txt` as a `local` source and overwrite
the plugin's as the first build command:

```yaml
  - kind: local
    path: elements/<name>/files/modules.txt   # regenerate on version bumps:
                                              # clone tag, `go mod vendor`,
                                              # copy vendor/modules.txt
config:
  build-commands:
    - mv -vf modules.txt vendor/modules.txt
```

When is the shipped file skippable? Only when ALL of: no replace
directives, no `// indirect` requires, and (to be safe) a pre-1.14 go
directive. `elements/go-md2man/go-md2man.bst` is the in-repo example of
that minimal case. Default to shipping modules.txt.

## RE-grid Go environment (mandatory)

Builds on the ghost BuildBarn grid have **no network** — everything comes
from staged sources. This env block is proven (volcano, go-md2man):

```yaml
build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst  # shell for build-commands
  - freedesktop-sdk.bst:components/go.bst

environment:
  GOROOT: "%{libdir}/go"          # MANDATORY. Multiarch triplet: resolves to
                                  # /usr/lib/x86_64-linux-gnu/go, NOT /usr/lib/go.
  GOPATH: "%{build-root}/.gopath" # must be under build-root (writable)
  GOCACHE: "%{build-root}/.gocache"
  GOFLAGS: "-mod=vendor -buildvcs=false"  # never touch network or VCS
  CGO_ENABLED: "0"                # static binaries; add gcc et al. if you need cgo
```

Smoke-test the binary in a build command (it runs fine in the build
sandbox — same arch, static): capture output, `case`-match it, `exit 1` on
miss. See `elements/go-md2man/go-md2man.bst`.

## Vanity-import / track() crash workarounds

`track()` resolves non-GitHub modules by fetching
`https://<module>?go-get=1` and unpacking the meta tag into exactly
`(base, vcs, url)`. Two failure modes, both fixed the same way —
**hand-write the ref and comment the source out before running
`bst source track`**:

```yaml
  - kind: go_module
    url: github:cyphar/libpathrs.git        # real repo
    module: cyphar.com/go-pathrs            # vanity path from go.sum
    ref:
      go-version: v0.2.1
      git-ref: go-pathrs/v0.2.1-0-g6416ad69fa96f5465642b20af55f9e677b1d5d1d
      explicit: True
      subdirectory: go-pathrs               # module subdir inside the repo
```

- **4-field go-import meta** (e.g. `cyphar.com/go-pathrs`): the unpack
  raises `ValueError` and kills the whole track. Get the sha with
  `git ls-remote <repo> refs/tags/<tag>`; git-describe form is
  `<tag>-0-g<sha40>`.
- **Defunct vanity domain** (e.g. `stathat.com/c/consistent`): `?go-get=1`
  no longer resolves. Map to the historical GitHub repo, same hand-fill.
- **`+incompatible` pseudo-versions** (e.g. `github.com/mistifyio/go-zfs
  v2.1.2-0.20190413222219-f784269be439+incompatible`): the plugin's
  `PSEUDO_VERSION_REGEX` does not allow a `+incompatible` suffix, so
  `track()` dies with `version string ... not recognized`. Hand-fill with a
  **bare 40-char sha** as `git-ref` (REF_REGEX is
  `(?:(.*)(?:-(\d+)-g))?([0-9a-f]{40})` — tag optional; fetch does a full
  clone instead of a shallow tag fetch, slightly slower but fine). Expand
  the pseudo-version's short sha via
  `https://api.github.com/repos/<owner>/<repo>/commits/<shortsha>`.

To find every crasher in one pass instead of discovering them one 50-minute
track run at a time: download the project's `go.sum` and fullmatch each
non-`/go.mod` version against the plugin's two regexes
(`VERSION_REGEX`, `PSEUDO_VERSION_REGEX` in
`sources/go_module.py`). Anything matching neither is a hand-fill.

Note `subdirectory` in the ref: the plugin stages `<repo>/<subdirectory>`
into `vendor/<module>/`. For `v2+` modules without a subdirectory, staging
also auto-detects a major-version subdir (`v2/`) if one exists.

## Grid flakiness: CAS shard errors

If a build fails AFTER the remote build succeeded with
`Failed to obtain input file "...": Shard N: Object not found`, that is the
ghost bb-storage buildtree-caching bug, not your element. Retry with:

```
BST_FLAGS="--cache-buildtrees never" just bst build <element>
```

(Not seen on 2026-08-09 after the storage pods were restarted; both the
go-md2man and volcano builds passed without the flag.)

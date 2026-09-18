# BuildStream — Element Kinds and Source Kinds

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

## Element Kinds

| Kind | Use case | Used here for |
|---|---|---|
| `stack` | dependency aggregation only; **produces no filesystem output** | `<name>/<name>-stack.bst` |
| `compose` | filesystem-producing layer/filter step; applies `exclude:` domains | `<name>/<name>-runtime.bst` |
| `script` | image assembly — stages deps, runs commands, calls `build-oci` | `elements/oci/<name>.bst` |
| `manual` | custom build/install, pre-built binaries | tool elements |
| `import` | direct file placement, no build | file payloads |
| `make` / `meson` / `autotools` / `cmake` | matching upstream build system | source builds |
| `junction` | external project boundary | `elements/freedesktop-sdk.bst` |

`stack` vs `compose` is the single most common mistake: a `stack` aggregates
dependencies and emits **nothing** to the filesystem. If you expect files, you need
`compose`.

## Source Kinds

| Source kind | Use case |
|---|---|
| `git_repo` | most source trees (`ref-format: git-describe` is set project-wide) |
| `tar` | release tarballs — use `base-dir: ""` if there is no wrapping directory |
| `remote` | a single downloaded file |
| `local` | repo-local files |
| `patch_queue` | patch application — see [bst-junctions.md](../../bst-junctions/SKILL.md) |
| `go_module` | Go module dependencies (community plugin) |
| `cargo2` | Rust crate vendoring (community plugin) |

**Source URLs do not expand `%{variables}`.** Use an alias from
`include/aliases.yml` instead (`github:owner/repo.git`).

# BuildStream — Variables and Directive Syntax

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

## Key Variables

| Variable | Expands to | Notes |
|---|---|---|
| `%{install-root}` | staging dir | **prefix every install path with it** |
| `%{prefix}` | `/usr` | FSDK is merged-usr |
| `%{bindir}` | `/usr/bin` | binaries go here, not `/usr/sbin` |
| `%{indep-libdir}` | `/usr/lib` | arch-independent lib data |
| `%{datadir}` | `/usr/share` | data files |
| `%{sysconfdir}` | `/etc` | use sparingly |
| `%{install-extra}` | trailing hook | convention: end `install-commands` with it |
| `%{go-arch}` | `amd64` / `arm64` | repo-defined; used in `build-oci` blocks |
| `strip-binaries` | set to `""` to disable | **required for non-ELF payloads** |

## Directive Syntax

| Syntax | Meaning |
|---|---|
| `(@):` | include YAML from another file |
| `(?):` | conditional block, keyed on project options |
| `(>):` | **append** to an inherited list |
| `(<):` | **prepend** to an inherited list |

`(@)` composites at any mapping level, and the **including file wins** on conflict.
This repo already uses it for `include/aliases.yml` (in `project.conf`) and
`include/slim.yml` (under an element's `variables:`), which is the pattern to copy
when factoring shared commands out of elements.

**Option names may only contain alphanumerics and underscores.** A hyphenated name
like `my-option` is invalid — use `my_option`. This trips up agents copying names
from CLI flags.

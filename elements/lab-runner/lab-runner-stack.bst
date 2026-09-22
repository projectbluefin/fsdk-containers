# DO NOT EDIT. Generated from catalog/lab-runner.yaml by
# scripts/generate_image_elements.py (stack).
# Change the record, then run: just catalog-write

kind: stack
description: "Shell-enabled CI utility container carved from freedesktop-sdk \u2014\
  \ bash, curl, git, jq, python3, openssh"

# gzip is not optional alongside tar: GNU tar execs gzip as a child process for
# .tar.gz streams, so tar being present is not sufficient (#159).
#
# find, cmp, and diff3 ride in with the findutils/diffutils components already
# depended on above; they were undeclared in the gate even though xargs/diff
# from those same two components were (#74). projectbluefin/review vendored
# Python shims for exactly find and cmp because of that gap — declaring and
# gating all five commands (find, xargs, cmp, diff, diff3) plus the canonical
# tmux-256color terminfo record closes it without adding a new component.

depends:
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/curl.bst
  - freedesktop-sdk.bst:components/git.bst
  - freedesktop-sdk.bst:components/jq.bst
  - freedesktop-sdk.bst:components/python3.bst
  - freedesktop-sdk.bst:components/openssh.bst
  - freedesktop-sdk.bst:components/python3-pyyaml.bst
  - lab-runner/yq.bst
  - freedesktop-sdk.bst:components/bubblewrap.bst
  - freedesktop-sdk.bst:components/diffutils.bst
  - freedesktop-sdk.bst:components/file.bst
  - freedesktop-sdk.bst:components/findutils.bst
  - freedesktop-sdk.bst:components/gawk.bst
  - freedesktop-sdk.bst:components/gzip.bst
  - freedesktop-sdk.bst:components/less.bst
  - freedesktop-sdk.bst:components/patch.bst
  - freedesktop-sdk.bst:components/procps.bst
  - freedesktop-sdk.bst:components/tar.bst
  - freedesktop-sdk.bst:components/which.bst
  - lab-runner/shellcheck.bst
  - lab-runner/hadolint.bst
  - lab-runner/actionlint.bst
  - lab-runner/argo.bst
  - lab-runner/just.bst
  - lab-runner/kubectl.bst
  - lab-runner/nginx.bst
  - skopeo/skopeo-stack.bst

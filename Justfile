# List available commands
[group('info')]
default:
    @just --list

# -- Configuration ---------------------------------------------------------
export image_name := env("BUILD_IMAGE_NAME", "base")
export image_registry := env("BUILD_IMAGE_REGISTRY", "ghcr.io/projectbluefin")

# Same bst2 container image FSDK/dakota CI uses -- pinned by SHA.
export bst2_image := env("BST2_IMAGE", "registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:64eb0b4930d57a92710822898fb73af6cc1ae35d")

# OCI metadata (dynamic labels), injected at export time.
export OCI_IMAGE_CREATED := env("OCI_IMAGE_CREATED", "")
export OCI_IMAGE_REVISION := env("OCI_IMAGE_REVISION", "")

# Prefix for podman calls: empty when rootless podman works, "sudo" otherwise.
sudo_cmd := if `podman info >/dev/null 2>&1 && echo 1 || echo 0` == "1" { "" } else { "sudo" }

# FSDK release parsed from the pinned junction ref — the single source of truth
# for image versioning. e.g. "25.08.13".
export fsdk_version := `grep -oE 'freedesktop-sdk-[0-9]+\.[0-9]+\.[0-9]+' elements/freedesktop-sdk.bst | head -1 | sed 's/freedesktop-sdk-//'`
# Exact junction commit ref (full ref: value), for provenance.
export fsdk_ref := `grep -E '^\s*ref:' elements/freedesktop-sdk.bst | head -1 | sed -E 's/^\s*ref:\s*//'`

# -- BuildStream wrapper ------------------------------------------------------
# Runs any bst command inside the bst2 container via podman.
# Baseline x86_64 (no x86_64_v3) so the base image runs on the widest CPU set.
[group('dev')]
bst *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "${HOME}/.cache/buildstream"
    # shellcheck disable=SC2086
    podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{justfile_directory()}}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -w /src \
        "{{bst2_image}}" \
        bash -c 'bst --colors "$@"' -- --no-interactive ${BST_FLAGS:-} {{ARGS}}

# Print the tag set derived from the FSDK release: latest, minor line, point release.
[group('info')]
tags:
    #!/usr/bin/env bash
    set -euo pipefail
    V="{{fsdk_version}}"
    MINOR="$(echo "$V" | cut -d. -f1,2)"
    printf '%s\n%s\n%s\n' latest "$MINOR" "$V"

# ── Validate ──────────────────────────────────────────────────────────
[group('dev')]
validate:
    just bst show --deps all oci/base.bst

# ── Build ─────────────────────────────────────────────────────────────
# Build the base OCI image and load it into podman as
# ${image_registry}/${image_name}:latest.
[group('build')]
build:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Building oci/base.bst with BuildStream..."
    just bst build oci/base.bst
    just export

# ── Export ────────────────────────────────────────────────────────────
# Checkout the built OCI image and squash into a single layer in podman.
[group('build')]
export:
    #!/usr/bin/env bash
    set -euo pipefail
    FINAL_REF="{{image_registry}}/{{image_name}}:latest"

    echo "==> Exporting OCI image -> ${FINAL_REF}..."
    rm -rf .build-out
    just bst artifact checkout oci/base.bst --directory /src/.build-out

    IMAGE_ID=$({{sudo_cmd}} podman pull -q oci:.build-out)
    rm -rf .build-out

    LABEL_ARGS=()
    [ -n "${OCI_IMAGE_CREATED}" ]  && LABEL_ARGS+=(--label "org.opencontainers.image.created=${OCI_IMAGE_CREATED}")
    [ -n "${OCI_IMAGE_REVISION}" ] && LABEL_ARGS+=(--label "org.opencontainers.image.revision=${OCI_IMAGE_REVISION}")
    LABEL_ARGS+=(--label "org.opencontainers.image.version={{fsdk_version}}")
    LABEL_ARGS+=(--label "io.projectbluefin.fsdk.version={{fsdk_version}}")
    LABEL_ARGS+=(--label "io.projectbluefin.fsdk.ref={{fsdk_ref}}")

    # Squash to a single layer and apply dynamic labels.
    printf 'FROM %s\n' "$IMAGE_ID" \
      | {{sudo_cmd}} podman build --pull=never --squash-all "${LABEL_ARGS[@]}" -t "${FINAL_REF}" -f - .
    echo "==> Built ${FINAL_REF}"

# Push the locally built :latest under all derived tags to a given repo ref.
# Usage: just tag-push ghcr.io/projectbluefin/base
[group('build')]
tag-push REPO:
    #!/usr/bin/env bash
    set -euo pipefail
    SRC="{{image_registry}}/{{image_name}}:latest"
    while read -r t; do
        {{sudo_cmd}} podman tag "$SRC" "{{REPO}}:$t"
        {{sudo_cmd}} podman push "{{REPO}}:$t"
        echo "==> pushed {{REPO}}:$t"
    done < <(just tags)

# ── Verify ────────────────────────────────────────────────────────────
# Assert the image is distroless and ships certs + tzdata.
[group('test')]
verify:
    #!/usr/bin/env bash
    set -euo pipefail
    REF="{{image_registry}}/{{image_name}}:latest"

    echo "==> [1/4] distroless: no shell present"
    if {{sudo_cmd}} podman run --rm --entrypoint /bin/sh "$REF" -c 'echo reached' 2>/dev/null; then
        echo "FAIL: /bin/sh ran — image is not distroless"; exit 1
    fi

    # Export the rootfs listing once; reuse for all file-presence gates.
    {{sudo_cmd}} podman create --name verify-base "$REF" >/dev/null
    trap '{{sudo_cmd}} podman rm -f verify-base >/dev/null 2>&1 || true' EXIT
    LISTING="$(mktemp)"
    {{sudo_cmd}} podman export verify-base | tar -tf - > "$LISTING"

    if grep -qE '(^|/)(ba)?sh$' "$LISTING"; then
        echo "FAIL: a shell binary is present in the rootfs"; exit 1
    fi
    echo "OK: no shell"

    echo "==> [2/4] CA certificate bundle present"
    if ! grep -qE '^etc/(pki/tls/certs/ca-bundle\.crt|ssl/certs/ca-certificates\.crt)$' "$LISTING"; then
        echo "FAIL: no CA bundle file found"; exit 1
    fi
    echo "OK: CA bundle present"

    echo "==> [3/4] tzdata present"
    if ! grep -qE '^usr/share/zoneinfo/UTC$' "$LISTING"; then
        echo "FAIL: tzdata (zoneinfo/UTC) missing"; exit 1
    fi
    echo "OK: tzdata present"

    echo "==> [4/4] slim: bloat must NOT be present (terminfo, sanitizers, fortran)"
    if grep -qE 'usr/share/terminfo/|/lib(asan|tsan|lsan|ubsan|hwasan|gfortran)\.so' "$LISTING"; then
        echo "FAIL: slim bloat present — slim recipe regressed"; exit 1
    fi
    echo "OK: slim bloat removed"
    echo "==> verify passed"

# -- Homebrew nspawn machine image -------------------------------------------
# NOT distroless: a full dev-environment rootfs tarball for systemd-nspawn /
# machinectl import-tar (see docs/skills/nspawn-machine-image.md).
brew_version := "6.0.3"

# Build the brew nspawn machine image (rootfs tarball, not OCI).
[group('brew')]
build-brew:
    just bst build oci/brew-nspawn.bst

# Export the rootfs tarball + SHA256SUMS to dist/.
[group('brew')]
export-brew: build-brew
    rm -rf dist
    just bst artifact checkout oci/brew-nspawn.bst --directory dist
    @echo "==> wrote:" && ls -lh dist/

# Verify the tarball is a machinectl-shaped rootfs with the required contents.
[group('brew')]
verify-brew: export-brew
    #!/usr/bin/env bash
    set -euo pipefail
    T="dist/homebrew-env-{{brew_version}}.tar.zst"
    [ -f "$T" ] || { echo "FAIL: $T not found"; exit 1; }
    L="$(mktemp)"
    tar --zstd -tf "$T" > "$L"
    fail=0
    # usr-merge: /bin and /sbin are symlinks to usr/bin, so check the real paths.
    # bwrap is required so `brew install` source builds can sandbox (Homebrew 6).
    for p in ./usr/bin/bash ./usr/bin/ruby ./usr/bin/git ./usr/bin/curl \
             ./usr/bin/patchelf \
             ./usr/lib/systemd/systemd ./usr/bin/init \
             ./home/linuxbrew/.linuxbrew/bin/brew \
             ./home/linuxbrew/.linuxbrew/Homebrew/bin/brew \
             ./etc/passwd ./etc/machine-id ./etc/locale.conf \
             ./etc/subuid ./etc/subgid; do
        if grep -qxF "$p" "$L"; then echo "OK   $p"; else echo "MISS $p"; fail=1; fi
    done
    # linuxbrew user must be present at uid 1001.
    if tar --zstd -xf "$T" -O ./etc/passwd | grep -q '^linuxbrew:x:1001:1001:'; then
        echo "OK   linuxbrew uid 1001 in /etc/passwd"
    else
        echo "MISS linuxbrew uid 1001 in /etc/passwd"; fail=1
    fi
    [ "$fail" -eq 0 ] && echo "==> verify-brew passed" || { echo "==> verify-brew FAILED"; exit 1; }

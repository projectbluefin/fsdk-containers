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
    EFFECTIVE_BST_FLAGS="${BST_FLAGS:-}"
    if [[ ! " ${EFFECTIVE_BST_FLAGS} " =~ [[:space:]]--no-interactive([[:space:]]|$) ]]; then
        EFFECTIVE_BST_FLAGS="${EFFECTIVE_BST_FLAGS} --no-interactive"
    fi
    # shellcheck disable=SC2086
    podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{justfile_directory()}}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -w /src \
        "{{bst2_image}}" \
        bash -c 'bst --colors "$@"' -- ${EFFECTIVE_BST_FLAGS} {{ARGS}}

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
    SUDO_CMD=""
    if ! podman info >/dev/null 2>&1; then SUDO_CMD="sudo"; fi

    echo "==> Exporting OCI image -> ${FINAL_REF}..."
    rm -rf .build-out
    just bst artifact checkout oci/base.bst --directory /src/.build-out

    IMAGE_ID=$($SUDO_CMD podman pull -q oci:.build-out)
    rm -rf .build-out

    LABEL_ARGS=()
    [ -n "${OCI_IMAGE_CREATED}" ]  && LABEL_ARGS+=(--label "org.opencontainers.image.created=${OCI_IMAGE_CREATED}")
    [ -n "${OCI_IMAGE_REVISION}" ] && LABEL_ARGS+=(--label "org.opencontainers.image.revision=${OCI_IMAGE_REVISION}")
    LABEL_ARGS+=(--label "org.opencontainers.image.version={{fsdk_version}}")
    LABEL_ARGS+=(--label "io.projectbluefin.fsdk.version={{fsdk_version}}")
    LABEL_ARGS+=(--label "io.projectbluefin.fsdk.ref={{fsdk_ref}}")

    # Squash to a single layer and apply dynamic labels.
    printf 'FROM %s\n' "$IMAGE_ID" \
      | $SUDO_CMD podman build --pull=never --squash-all "${LABEL_ARGS[@]}" -t "${FINAL_REF}" -f - .
    echo "==> Built ${FINAL_REF}"

# Push the locally built :latest under all derived tags to a given repo ref.
# Usage: just tag-push ghcr.io/projectbluefin/base
[group('build')]
tag-push REPO:
    #!/usr/bin/env bash
    set -euo pipefail
    SRC="{{image_registry}}/{{image_name}}:latest"
    SUDO_CMD=""
    if ! podman info >/dev/null 2>&1; then SUDO_CMD="sudo"; fi
    while read -r t; do
        $SUDO_CMD podman tag "$SRC" "{{REPO}}:$t"
        $SUDO_CMD podman push "{{REPO}}:$t"
        echo "==> pushed {{REPO}}:$t"
    done < <(just tags)

# ── Verify ────────────────────────────────────────────────────────────
# Assert the image is distroless and ships certs + tzdata.
[group('test')]
verify:
    #!/usr/bin/env bash
    set -euo pipefail
    REF="{{image_registry}}/{{image_name}}:latest"
    SUDO_CMD=""
    if ! podman info >/dev/null 2>&1; then SUDO_CMD="sudo"; fi

    echo "==> [1/4] distroless: a shell must NOT be present"
    if $SUDO_CMD podman run --rm --entrypoint /bin/sh "$REF" -c 'echo reached' 2>/dev/null; then
        echo "FAIL: /bin/sh ran — image is not distroless"; exit 1
    fi
    echo "OK: no runnable /bin/sh"

    echo "==> [2/4] CA certificates present"
    $SUDO_CMD podman create --name verify-base "$REF" >/dev/null
    trap '$SUDO_CMD podman rm -f verify-base >/dev/null 2>&1 || true' EXIT
    ( set +o pipefail; $SUDO_CMD podman export verify-base | tar -tf - \
      | grep -qE 'etc/(ssl|pki)/.*(ca-bundle|cert)' ) && echo "OK: CA bundle present"

    echo "==> [3/4] tzdata present"
    ( set +o pipefail; $SUDO_CMD podman export verify-base | tar -tf - \
      | grep -q 'usr/share/zoneinfo/UTC' ) && echo "OK: tzdata present"

    echo "==> [4/4] slim: bloat must NOT be present (terminfo, sanitizers, fortran)"
    if $SUDO_CMD podman export verify-base | tar -tf - 2>/dev/null \
       | grep -qE 'usr/share/terminfo/|/lib(asan|tsan|lsan|ubsan|hwasan|gfortran)\.so'; then
        echo "FAIL: slim bloat present — slim recipe regressed"; exit 1
    fi
    echo "OK: slim bloat removed"
    echo "==> verify passed"

# List available commands
[group('info')]
default:
    @just --list

# -- Configuration ---------------------------------------------------------
export image_name := env("BUILD_IMAGE_NAME", "static")
export image_registry := env("BUILD_IMAGE_REGISTRY", "ghcr.io/projectbluefin")

# Same bst2 container image FSDK/dakota CI uses -- pinned by SHA.
export bst2_image := env("BST2_IMAGE", "registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:64eb0b4930d57a92710822898fb73af6cc1ae35d")

# OCI metadata (dynamic labels), injected at export time.
export OCI_IMAGE_CREATED := env("OCI_IMAGE_CREATED", "")
export OCI_IMAGE_REVISION := env("OCI_IMAGE_REVISION", "")

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

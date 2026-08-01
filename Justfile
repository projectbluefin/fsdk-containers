# List available commands
[group('info')]
default:
    @just --list

# -- Configuration ---------------------------------------------------------
export image_name := env("BUILD_IMAGE_NAME", "base")
export image_registry := env("BUILD_IMAGE_REGISTRY", "ghcr.io/projectbluefin")
# The tag the local build/verify/push recipes hand between each other. It is
# never published: keeping it distinct from any registry tag means a local
# working image can never be mistaken for, or accidentally pushed as, a
# released one.
local_tag := "build"

# Same bst2 container image FSDK/dakota CI uses -- pinned by SHA.
export bst2_image := env("BST2_IMAGE", "registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:64eb0b4930d57a92710822898fb73af6cc1ae35d")

# OCI metadata (dynamic labels), injected at export time.
export OCI_IMAGE_CREATED := env("OCI_IMAGE_CREATED", "")
export OCI_IMAGE_REVISION := env("OCI_IMAGE_REVISION", "")

# Prefix for podman calls: empty when rootless podman works, "sudo" otherwise.
sudo_cmd := if `podman info >/dev/null 2>&1 && echo 1 || echo 0` == "1" { "" } else { "sudo" }

# FSDK release parsed from the pinned junction ref — the single source of truth
# for image versioning. e.g. "25.08.14", "26.08beta.1", or "26.08.0".
export fsdk_version := `grep -E '^\s*ref:' elements/freedesktop-sdk.bst | head -1 | sed -E 's/.*freedesktop-sdk-//; s/-[0-9]+-g[0-9a-f]+$//'`
# Exact junction commit ref (full ref: value), for provenance.
export fsdk_ref := `grep -E '^\s*ref:' elements/freedesktop-sdk.bst | head -1 | sed -E 's/^\s*ref:\s*//'`

# -- BuildStream wrapper ------------------------------------------------------
# Runs any bst command inside the bst2 container via podman.
# Baseline x86_64 (no x86_64_v3) so the base image runs on the widest CPU set.
#
# Builds are submitted to the ghost cluster's BuildBarn remote-execution grid
# by default for local/agent builds: the in-cluster frontend
# (frontend.buildbarn.svc:8980, plain gRPC) is reached via kubectl
# port-forward, so compile actions run on the cluster workers, NOT on this
# machine. Exceptions:
#   - BST_LOCAL=1        force local execution (offline, or grid is down)
#   - CI (GITHUB_ACTIONS) always local: runners build natively per-arch and the
#     grid is x86_64-only (no aarch64 RE workers yet)
# If the cluster is unreachable the recipe FAILS (no silent local fallback) —
# set BST_LOCAL=1 explicitly to build locally. See docs/skills/remote-execution.md.
[group('dev')]
bst *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "${HOME}/.cache/buildstream"
    # Regenerated on every invocation from {{fsdk_version}} (this Justfile's
    # own single source of truth, parsed from elements/freedesktop-sdk.bst's
    # pinned ref) so BuildStream elements can consume the exact point
    # release via `(@): include/fsdk-version.yml` without re-parsing it
    # independently. Gitignored; never hand-edited. See
    # docs/skills/vm-podman-guest.md.
    cat > include/fsdk-version.yml <<'EOF'
    fsdk-version: "{{fsdk_version}}"
    EOF
    RE_FLAG=()
    PF_PID=""
    cleanup() { [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null || true; }
    trap cleanup EXIT
    if [ "${BST_LOCAL:-0}" != "1" ] && [ "${GITHUB_ACTIONS:-}" != "true" ]; then
        export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/bluespeed.yaml}"
        if ! kubectl get svc frontend -n buildbarn >/dev/null 2>&1; then
            echo "ERROR: ghost cluster BuildBarn frontend unreachable (KUBECONFIG=$KUBECONFIG)." >&2
            echo "       Builds must run on the cluster. If it is down, rerun with BST_LOCAL=1." >&2
            exit 1
        fi
        kubectl port-forward -n buildbarn svc/frontend 18980:8980 >/dev/null 2>&1 &
        PF_PID=$!
        for _ in $(seq 1 20); do
            (echo > /dev/tcp/127.0.0.1/18980) 2>/dev/null && break
            sleep 0.5
        done
        cat > .bst-re.conf <<'EOF'
    remote-execution:
      execution-service:
        url: grpc://127.0.0.1:18980
        connection-config:
          keepalive-time: 60
          retry-limit: 8
          retry-delay: 1000
          request-timeout: 1800
      storage-service:
        url: grpc://127.0.0.1:18980
        connection-config:
          keepalive-time: 60
          retry-limit: 8
          retry-delay: 1000
          request-timeout: 1800
      action-cache-service:
        url: grpc://127.0.0.1:18980
        connection-config:
          keepalive-time: 60
          retry-limit: 8
          retry-delay: 1000
          request-timeout: 1800
    EOF
        RE_FLAG=(--config /src/.bst-re.conf)
        echo "==> BuildStream remote execution: ghost cluster BuildBarn grid (via port-forward :18980). Set BST_LOCAL=1 for local builds." >&2
    else
        echo "==> BuildStream LOCAL execution" >&2
    fi
    # shellcheck disable=SC2086
    {{sudo_cmd}} podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{justfile_directory()}}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -w /src \
        "{{bst2_image}}" \
        bash -c 'bst --colors "$@"' -- --no-interactive "${RE_FLAG[@]}" ${BST_FLAGS:-} {{ARGS}}

# Print the tag set derived from the FSDK release: minor line and point
# release/beta tag. Deliberately no "latest": a mutable rolling alias invites
# consumers to deploy an unpinned image and silently changes what they run.
# Every published tag here is either immutable (the point release) or moves
# only within a declared minor line, so a consumer always states how much
# drift they accept. Pin by digest when even that is too much.
[group('info')]
tags:
    #!/usr/bin/env bash
    set -euo pipefail
    V="{{fsdk_version}}"
    MINOR="$(echo "$V" | grep -oE '^[0-9]+\.[0-9]+')"
    if [ "$V" = "$MINOR" ]; then
        printf '%s\n' "$V"
    else
        printf '%s\n%s\n' "$MINOR" "$V"
    fi

# Print the OCI image names from the canonical manifest (elements/targets.json),
# one per line. Single source of truth for the GHA build/manifest matrices,
# `just validate`, and `just sbom`/`sboms` -- add a package here once, nowhere else.
[group('info')]
image-list:
    @jq -r '.oci_images[]' elements/targets.json

# Print the OCI image names as a JSON array, for GitHub Actions `fromJson()` matrices.
[group('info')]
image-matrix:
    @jq -c '.oci_images' elements/targets.json

# ── Validate ──────────────────────────────────────────────────────────
[group('dev')]
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    ELEMENTS=()
    while IFS= read -r img; do
        ELEMENTS+=("oci/${img}.bst")
    done < <(just image-list)
    just bst show --deps all "${ELEMENTS[@]}" podman-vm/podman-vm-efi.bst

# ── Build ─────────────────────────────────────────────────────────────
# Build one OCI image (controlled by BUILD_IMAGE_NAME) and load into podman.
[group('build')]
build:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Building oci/{{image_name}}.bst with BuildStream..."
    just bst build "oci/{{image_name}}.bst"
    just export

# ── Export ────────────────────────────────────────────────────────────
# Checkout the built OCI image and squash into a single layer in podman.
[group('build')]
export:
    #!/usr/bin/env bash
    set -euo pipefail
    FINAL_REF="{{image_registry}}/{{image_name}}:{{local_tag}}"

    echo "==> Exporting OCI image -> ${FINAL_REF}..."
    rm -rf .build-out
    just bst artifact checkout "oci/{{image_name}}.bst" --directory /src/.build-out

    IMAGE_ID=$({{sudo_cmd}} podman pull -q oci:.build-out)
    rm -rf .build-out

    case "{{image_name}}" in
        base)       DESC="Minimal, high-integrity distroless base image built on freedesktop-sdk" ;;
        static)     DESC="Static-tier runner for compiled Go/Rust binaries built on freedesktop-sdk" ;;
        skopeo)     DESC="Skopeo OCI image utility built on freedesktop-sdk" ;;
        lab-runner) DESC="Shell-enabled CI/CD utility container for Project Bluefin workflows" ;;
        python)     DESC="Minimal, high-integrity distroless Python 3 runtime built on freedesktop-sdk" ;;
        buildah)    DESC="Distroless Buildah container-building tool built on freedesktop-sdk" ;;
        qemu-img)   DESC="Distroless qemu-img disk image utility built on freedesktop-sdk" ;;
        *)          DESC="Project Bluefin distroless container image" ;;
    esac

    LABEL_ARGS=()
    [ -n "${OCI_IMAGE_CREATED}" ]  && LABEL_ARGS+=(--label "org.opencontainers.image.created=${OCI_IMAGE_CREATED}")
    [ -n "${OCI_IMAGE_REVISION}" ] && LABEL_ARGS+=(--label "org.opencontainers.image.revision=${OCI_IMAGE_REVISION}")
    LABEL_ARGS+=(--label "org.opencontainers.image.version={{fsdk_version}}")
    LABEL_ARGS+=(--label "org.opencontainers.image.title={{image_name}}")
    LABEL_ARGS+=(--label "org.opencontainers.image.description=${DESC}")
    LABEL_ARGS+=(--label "org.opencontainers.image.source=https://github.com/projectbluefin/fsdk-containers")
    LABEL_ARGS+=(--label "org.opencontainers.image.licenses=Apache-2.0")
    LABEL_ARGS+=(--label "io.projectbluefin.fsdk.version={{fsdk_version}}")
    LABEL_ARGS+=(--label "io.projectbluefin.fsdk.ref={{fsdk_ref}}")

    # Squash to a single layer and apply dynamic labels.
    printf 'FROM %s\n' "$IMAGE_ID" \
      | {{sudo_cmd}} podman build --pull=never --squash-all "${LABEL_ARGS[@]}" -t "${FINAL_REF}" -f - .
    echo "==> Built ${FINAL_REF}"

# Push the locally built image under all derived tags to a given repo ref.
# The FSDK point-release tag (e.g. :25.08.13) is treated as immutable: if it
# already exists at the destination it is skipped, never overwritten.
# Usage: just tag-push ghcr.io/projectbluefin/base
[group('build')]
tag-push REPO:
    #!/usr/bin/env bash
    set -euo pipefail
    SRC="{{image_registry}}/{{image_name}}:{{local_tag}}"
    while read -r t; do
        if [ "$t" = "{{fsdk_version}}" ] && skopeo inspect --no-tags "docker://{{REPO}}:$t" >/dev/null 2>&1; then
            echo "==> skipping {{REPO}}:$t (point-release tag already published, immutable)"
            continue
        fi
        {{sudo_cmd}} podman tag "$SRC" "{{REPO}}:$t"
        {{sudo_cmd}} podman push "{{REPO}}:$t"
        echo "==> pushed {{REPO}}:$t"
    done < <(just tags)

# Push the locally built image to Quay.io with zstd:chunked compression.
# Usage: just push-quay quay.io/yourusername/base
[group('build')]
push-quay REPO:
    #!/usr/bin/env bash
    set -euo pipefail
    SRC="{{image_registry}}/{{image_name}}:{{local_tag}}"
    while read -r t; do
        echo "==> Tagging $SRC to {{REPO}}:$t..."
        {{sudo_cmd}} podman tag "$SRC" "{{REPO}}:$t"
        echo "==> Pushing {{REPO}}:$t with zstd:chunked compression..."
        {{sudo_cmd}} podman push --compression-format zstd:chunked --force-compression "{{REPO}}:$t"
    done < <(just tags)

# ── Verify ────────────────────────────────────────────────────────────
# Assert the image meets its contract: distroless images have no shell;
# all images ship CA certs + tzdata (except static-tier Go binaries which
# carry these in their own layer); lab-runner explicitly keeps a shell.
[group('test')]
verify:
    #!/usr/bin/env bash
    set -euo pipefail
    REF="{{image_registry}}/{{image_name}}:{{local_tag}}"
    IMG="{{image_name}}"

    # Guard against silent size creep. These are uncompressed local Podman
    # sizes (not registry transfer sizes), with headroom for FSDK growth.
    case "$IMG" in
        base)       MAX_BYTES=$((64 * 1024 * 1024)) ;;
        static)     MAX_BYTES=$((80 * 1024 * 1024)) ;;
        skopeo)     MAX_BYTES=$((224 * 1024 * 1024)) ;;
        python)     MAX_BYTES=$((144 * 1024 * 1024)) ;;
        qemu-img)   MAX_BYTES=$((192 * 1024 * 1024)) ;;
        buildah)    MAX_BYTES=$((256 * 1024 * 1024)) ;;
        lab-runner) MAX_BYTES=$((320 * 1024 * 1024)) ;;
        *)          echo "FAIL: no size threshold configured for $IMG" >&2; exit 1 ;;
    esac
    SIZE_BYTES=$({{sudo_cmd}} podman image inspect --format '{{"{{.Size}}"}}' "$REF")
    if ! [[ "$SIZE_BYTES" =~ ^[0-9]+$ ]] || [ "$SIZE_BYTES" -gt "$MAX_BYTES" ]; then
        echo "FAIL: $IMG image size ${SIZE_BYTES} bytes exceeds ${MAX_BYTES} bytes" >&2
        exit 1
    fi
    echo "OK: image size ${SIZE_BYTES} bytes (limit ${MAX_BYTES})"

    {{sudo_cmd}} podman create --name verify-base "$REF" /verify-placeholder >/dev/null
    trap '{{sudo_cmd}} podman rm -f verify-base >/dev/null 2>&1 || true' EXIT
    LISTING="$(mktemp)"
    {{sudo_cmd}} podman export verify-base | tar -tf - > "$LISTING"

    GATE=1
    if [ "$IMG" = "lab-runner" ]; then
        echo "==> [${GATE}/${GATE}] shell present (lab-runner is intentionally shell-enabled)"
        if ! grep -qE '(^|/)bash$' "$LISTING"; then
            echo "FAIL: bash missing from lab-runner — shell must be present"; exit 1
        fi
        echo "OK: bash present"
        TOTAL=2
        echo "==> [2/${TOTAL}] lab-runner CLI tools present"
        for tool in argo just kubectl; do
            if ! grep -qE "(^|/)${tool}$" "$LISTING"; then
                echo "FAIL: ${tool} missing from lab-runner"; exit 1
            fi
        done
        echo "OK: argo, just, and kubectl present"
    else
        TOTAL=5
        echo "==> [1/${TOTAL}] distroless: no shell present"
        if grep -qE '(^|/)(ba)?sh$' "$LISTING"; then
            echo "FAIL: a shell binary is present in the rootfs"; exit 1
        fi
        echo "OK: no shell"

        echo "==> [2/${TOTAL}] CA certificate bundle present"
        if ! grep -qE '^etc/(pki/tls/certs/ca-bundle\.crt|ssl/certs/ca-certificates\.crt)$' "$LISTING"; then
            echo "FAIL: no CA bundle file found"; exit 1
        fi
        echo "OK: CA bundle present"

        echo "==> [3/${TOTAL}] tzdata present"
        if ! grep -qE '^usr/share/zoneinfo/UTC$' "$LISTING"; then
            echo "FAIL: tzdata (zoneinfo/UTC) missing"; exit 1
        fi
        echo "OK: tzdata present"

        echo "==> [4/${TOTAL}] slim: bloat must NOT be present (terminfo, sanitizers, fortran)"
        if grep -qE 'usr/share/terminfo/|/lib(asan|tsan|lsan|ubsan|hwasan|gfortran)\.so' "$LISTING"; then
            echo "FAIL: slim bloat present — slim recipe regressed"; exit 1
        fi
        echo "OK: slim bloat removed"

        echo "==> [5/${TOTAL}] slim: locale/build-tool bloat must NOT be present"
        if grep -qE 'usr/lib(/[^/]*)?/locale/locale-archive$|usr/share/i18n/charmaps/|/(localedef|sln|iconvconfig|ldconfig|pcre2test|pcre2grep)$|libpcre2-(16|32|posix)\.so' "$LISTING"; then
            echo "FAIL: locale/build-tool bloat present — slim recipe regressed"; exit 1
        fi
        echo "OK: locale/build-tool bloat removed"
    fi

    echo "==> smoke test (executing binary)"
    if [ "$IMG" = "skopeo" ]; then
        if ! {{sudo_cmd}} podman run --rm "$REF" skopeo --version >/dev/null; then
            echo "FAIL: skopeo failed to execute"; exit 1
        fi
        echo "OK: skopeo executes successfully"
    elif [ "$IMG" = "python" ]; then
        if ! {{sudo_cmd}} podman run --rm "$REF" --version >/dev/null; then
            echo "FAIL: python failed to execute"; exit 1
        fi
        echo "OK: python executes successfully"
    elif [ "$IMG" = "buildah" ]; then
        if ! {{sudo_cmd}} podman run --rm "$REF" --version >/dev/null; then
            echo "FAIL: buildah failed to execute"; exit 1
        fi
        echo "OK: buildah executes successfully"
    elif [ "$IMG" = "qemu-img" ]; then
        if ! {{sudo_cmd}} podman run --rm "$REF" --version >/dev/null; then
            echo "FAIL: qemu-img failed to execute"; exit 1
        fi
        echo "OK: qemu-img executes successfully"
    elif [ "$IMG" = "lab-runner" ]; then
        if ! {{sudo_cmd}} podman run --rm "$REF" -c "curl --version && git --version && jq --version && python3 --version" >/dev/null; then
            echo "FAIL: lab-runner tools failed to execute"; exit 1
        fi
        echo "OK: lab-runner tools execute successfully"
    fi

    echo "==> verify passed (${IMG})"

# -- Donate-clanker VM guest disk image --------------------------------------
# Full-OS, shell-enabled bootable EFI/raw donate-clanker guest (see
# docs/skills/vm-podman-guest.md). NOT an OCI image: never loaded into
# Podman, only checked out and published as versioned GitHub Release assets.

# Build the podman-vm-efi.bst element (BuildStream build only, no export).
[group('vm')]
build-podman-vm:
    just bst build podman-vm/podman-vm-efi.bst

# Check out ONLY the element's install-root -- the raw disk plus its .sha256
# manifest -- into dist-vm/. Deliberately does NOT load it into Podman as an
# OCI image (this is a bootable VM disk, not a container layer).
[group('vm')]
export-podman-vm: build-podman-vm
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf dist-vm
    just bst artifact checkout podman-vm/podman-vm-efi.bst --directory dist-vm
    echo "==> wrote:" && ls -lh dist-vm/

# Convert the exported raw disk to QCOW2 alongside it (requires the
# `qemu-img` binary from the `qemu-utils` package on the runner/host -- this
# is a lightweight format conversion, not a BuildStream build, so it is a
# plain Just recipe rather than its own element). Produces
# donate-clanker-vm-<version>-<arch>.qcow2 plus its own
# `sha256sum --binary` manifest, matching the raw disk's checksum shape.
[group('vm')]
export-podman-vm-qcow2: export-podman-vm
    #!/usr/bin/env bash
    set -euo pipefail
    command -v qemu-img >/dev/null 2>&1 || { echo "FAIL: qemu-img not found -- install the 'qemu-utils' package" >&2; exit 1; }
    shopt -s nullglob
    raws=(dist-vm/donate-clanker-vm-*.raw)
    shopt -u nullglob
    if [ "${#raws[@]}" -ne 1 ]; then
        echo "FAIL: expected exactly one raw VM disk in dist-vm/ (run 'just export-podman-vm' first), found ${#raws[@]}" >&2
        exit 1
    fi
    raw="$(basename "${raws[0]}")"
    qcow2="${raw%.raw}.qcow2"
    echo "==> converting ${raw} -> ${qcow2}..."
    qemu-img convert -f raw -O qcow2 "dist-vm/${raw}" "dist-vm/${qcow2}"
    ( cd dist-vm && sha256sum --binary "${qcow2}" > "${qcow2}.sha256" )
    echo "==> wrote:" && ls -lh "dist-vm/${qcow2}" "dist-vm/${qcow2}.sha256"

# Upload the built VM guest artifacts (raw disk + QCOW2, each with its own
# SHA-256 manifest) as immutable GitHub Release assets under the current
# FSDK point-release tag (vX.Y.Z). Mirrors the OCI `tag-push` recipe:
# operates on whatever is already in dist-vm/ (from `just export-podman-vm`
# and, optionally, `just export-podman-vm-qcow2`, run separately -- e.g.
# once per arch in CI, artifact handed off between jobs) rather than forcing
# a rebuild on every publish. Also mirrors `tag-push`'s immutability guard:
# an asset that already exists on the release is never overwritten. Never
# publishes a mutable "latest" URL for launcher consumption -- see
# docs/skills/vm-podman-guest.md. Requires `gh` authenticated with
# `contents: write` on THIS repo (the workflow's default GITHUB_TOKEN is
# sufficient -- this is a same-repo release upload, not a cross-repo write,
# so the org's PAT ban / Mergeraptor requirement does not apply; see
# docs/skills/ci-tooling.md).
[group('vm')]
publish-podman-vm:
    #!/usr/bin/env bash
    set -euo pipefail
    TAG="v{{fsdk_version}}"
    shopt -s nullglob
    raws=(dist-vm/donate-clanker-vm-*.raw)
    qcow2s=(dist-vm/donate-clanker-vm-*.qcow2)
    shopt -u nullglob
    if [ "${#raws[@]}" -ne 1 ]; then
        echo "FAIL: expected exactly one raw VM disk in dist-vm/ (run 'just export-podman-vm' first), found ${#raws[@]}" >&2
        exit 1
    fi
    if [ "${#qcow2s[@]}" -gt 1 ]; then
        echo "FAIL: expected at most one QCOW2 VM disk in dist-vm/, found ${#qcow2s[@]}" >&2
        exit 1
    fi
    # Asset pairs: each disk image plus its checksum manifest. QCOW2 is
    # optional -- callers that only ran `just export-podman-vm` still publish
    # the raw disk alone.
    assets=("${raws[0]}" "${raws[0]}.sha256")
    if [ "${#qcow2s[@]}" -eq 1 ]; then
        assets+=("${qcow2s[0]}" "${qcow2s[0]}.sha256")
    fi
    for f in "${assets[@]}"; do
        [ -f "$f" ] || { echo "FAIL: $f not found" >&2; exit 1; }
    done

    if ! gh release view "$TAG" >/dev/null 2>&1; then
        echo "==> creating release $TAG (none exists yet)"
        gh release create "$TAG" --title "Release ${TAG}" \
            --notes "Freedesktop-SDK {{fsdk_version}} container image release."
    fi

    EXISTING="$(gh release view "$TAG" --json assets --jq '.assets[].name')"
    for disk in "${raws[0]}" "${qcow2s[@]:-}"; do
        [ -n "$disk" ] || continue
        name="$(basename "$disk")"
        if echo "$EXISTING" | grep -qxF "$name"; then
            echo "==> skipping ${name} (point-release asset already published, immutable)"
        else
            gh release upload "$TAG" "$disk" "${disk}.sha256"
            echo "==> uploaded ${name} + checksum to release ${TAG}"
        fi
    done

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
    # Run smoke checks inside the brew machine container.
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

# Install and configure the local brew nspawn container (requires sudo).
[group('brew')]
install-brew: verify-brew
    #!/usr/bin/env bash
    set -euo pipefail
    T="dist/homebrew-env-{{brew_version}}.tar.zst"
    [ -f "$T" ] || { echo "FAIL: $T not found"; exit 1; }

    echo "==> Importing brew container as machine 'homebrew'..."
    if sudo machinectl list-images --no-legend | grep -q "^homebrew\b"; then
        echo "==> Removing existing homebrew machine image..."
        sudo machinectl terminate homebrew >/dev/null 2>&1 || true
        sudo machinectl remove homebrew || true
    fi
    sudo machinectl import-tar "$T" homebrew

    echo "==> Setting up nspawn configuration at /etc/systemd/nspawn/homebrew.nspawn..."
    sudo mkdir -p /etc/systemd/nspawn
    { \
        echo "[Exec]"; \
        echo "PrivateUsers=no"; \
        echo "ResolvConf=bind-host"; \
        echo "DropCapability=CAP_SYS_ADMIN CAP_SYS_PTRACE CAP_NET_ADMIN CAP_SYS_RAWIO CAP_SYS_MODULE CAP_AUDIT_CONTROL"; \
        echo "SystemCallFilter=~@mount @reboot @swap @obsolete"; \
        echo "NoNewPrivileges=yes"; \
        echo ""; \
        echo "[Files]"; \
        echo "Bind=/home/linuxbrew"; \
        echo ""; \
        echo "[Network]"; \
        echo "VirtualEthernet=no"; \
    } | sudo tee /etc/systemd/nspawn/homebrew.nspawn >/dev/null

    echo "==> Creating /home/linuxbrew on the host..."
    sudo mkdir -p /home/linuxbrew
    sudo chown 1001:1001 /home/linuxbrew

    echo "==> Starting homebrew container..."
    sudo machinectl start homebrew
    echo "==> Waiting for systemd inside the container to boot..."
    sleep 3
    echo "==> Homebrew container successfully installed and booted!"
    echo "==> You can now run brew commands using: just run-brew <command>"

# Run a brew command inside the imported homebrew container (e.g. just run-brew install hello).
[group('brew')]
run-brew *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! sudo machinectl list --no-legend | grep -q "^homebrew\b"; then
        if sudo machinectl list-images --no-legend | grep -q "^homebrew\b"; then
            echo "==> Starting homebrew container..."
            sudo machinectl start homebrew
            sleep 2
        else
            echo "ERROR: homebrew container is not installed. Run 'just install-brew' first." >&2
            exit 1
        fi
    fi
    sudo systemd-run --quiet --pipe --wait --machine=homebrew --uid=linuxbrew \
        --setenv=HOMEBREW_NO_AUTO_UPDATE=1 --setenv=HOMEBREW_NO_INSTALL_CLEANUP=1 \
        -- /home/linuxbrew/.linuxbrew/bin/brew {{ARGS}}

# Stop and remove the homebrew container and its files (requires sudo).
[group('brew')]
uninstall-brew:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Stopping homebrew container..."
    sudo machinectl terminate homebrew >/dev/null 2>&1 || true
    echo "==> Removing homebrew machine image..."
    sudo machinectl remove homebrew >/dev/null 2>&1 || true
    echo "==> Cleaning up /etc/systemd/nspawn/homebrew.nspawn..."
    sudo rm -f /etc/systemd/nspawn/homebrew.nspawn
    echo "==> Done. Note: /home/linuxbrew is left intact. Remove it manually if desired."

# Generate a BST-native SBOM (SPDX 2.3) using buildstream-sbom. `variant` is
# any name from the elements/targets.json manifest, or the special value
# "podman-vm" for the VM guest disk (not part of the OCI manifest).
[group('test')]
sbom variant="base":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{variant}}" = "podman-vm" ]; then
        ELEMENT="podman-vm/podman-vm-efi.bst"
        SPDX_NAME="podman-vm"
    elif jq -e --arg v "{{variant}}" '.oci_images | index($v) != null' elements/targets.json >/dev/null; then
        ELEMENT="oci/{{variant}}.bst"
        SPDX_NAME="{{variant}}"
    else
        echo "ERROR: unknown variant '{{variant}}' (not in elements/targets.json, not 'podman-vm')" >&2
        exit 1
    fi
    OUTFILE="${SPDX_NAME}.spdx.json"
    mkdir -p "${HOME}/.cache/buildstream"
    mkdir -p "${HOME}/.cache/pip"
    GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

    {{sudo_cmd}} podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{justfile_directory()}}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -v "${HOME}/.cache/pip:/root/.cache/pip:rw" \
        -w /src \
        -e ELEMENT="${ELEMENT}" \
        -e SPDX_NAME="${SPDX_NAME}" \
        -e OUTFILE="${OUTFILE}" \
        -e GIT_SHA="${GIT_SHA}" \
        "{{bst2_image}}" \
        bash -c '
            for attempt in 1 2 3; do
                pip install --quiet \
                    git+https://gitlab.com/BuildStream/buildstream-sbom.git@0706fec3bedf6f73bd9d2fed32c2aed585feef8d \
                    && break
                echo "buildstream-sbom install failed (attempt ${attempt}/3); retrying in 5s..."
                [ "${attempt}" -lt 3 ] && sleep 5
            done
            buildstream-sbom "${ELEMENT}" \
                --spdx-name "${SPDX_NAME}" \
                --spdx-namespace "https://github.com/projectbluefin/fsdk-containers/sbom/${GIT_SHA}/${SPDX_NAME}" \
                --spdx-creator "Tool: buildstream-sbom" \
                --spdx-creator "Organization: projectbluefin" \
                --deps all \
                --output "/src/${OUTFILE}"
        '

# Generate BuildStream-native SBOMs for all images in a single optimized container run
[group('test')]
sboms:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "${HOME}/.cache/buildstream"
    mkdir -p "${HOME}/.cache/pip"
    GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    # Read the manifest on the host (jq is a GHA-runner/host dependency, not a
    # bst2-container one) so the container loop below never needs its own
    # copy of the image list.
    IMAGES="$(jq -r '.oci_images | join(" ")' elements/targets.json)"

    {{sudo_cmd}} podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{justfile_directory()}}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -v "${HOME}/.cache/pip:/root/.cache/pip:rw" \
        -w /src \
        -e GIT_SHA="${GIT_SHA}" \
        -e IMAGES="${IMAGES}" \
        "{{bst2_image}}" \
        bash -c '
            for attempt in 1 2 3; do
                pip install --quiet \
                    git+https://gitlab.com/BuildStream/buildstream-sbom.git@0706fec3bedf6f73bd9d2fed32c2aed585feef8d \
                    && break
                echo "buildstream-sbom install failed (attempt ${attempt}/3); retrying in 5s..."
                [ "${attempt}" -lt 3 ] && sleep 5
            done
            for img in ${IMAGES}; do
                ELEMENT="oci/${img}.bst"
                echo "==> Generating SBOM for ${img}..."
                buildstream-sbom "${ELEMENT}" \
                    --spdx-name "${img}" \
                    --spdx-namespace "https://github.com/projectbluefin/fsdk-containers/sbom/${GIT_SHA}/${img}" \
                    --spdx-creator "Tool: buildstream-sbom" \
                    --spdx-creator "Organization: projectbluefin" \
                    --deps all \
                    --output "/src/${img}.spdx.json"
            done
        '

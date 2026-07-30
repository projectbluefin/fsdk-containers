kind: script
description: |
  Assemble the generic, shell-enabled Podman VM guest disk image.

  Stages `podman-vm-filesystem.bst` at `/sysroot` (root partition content)
  and freedesktop-sdk.bst's own `vm/boot/efi.bst` at `/sysroot/efi` (EFI
  System Partition content, reused byte-for-byte unmodified — exactly how
  freedesktop-sdk.bst's own `vm/minimal/efi.bst` composes the same two
  pieces), then runs the identical `genimage`-based GPT disk assembler
  (`vm/deploy-tools.bst` + `vm/prepare-image.bst` + `components/fakecap.bst`)
  to emit a raw disk.img. Unlike upstream's own `vm/minimal/efi.bst` (whose
  install-root *is* the raw disk.img), this element treats disk.img as a
  build-only intermediate: it is converted with this project's own
  `qemu-img/qemu-img-stack.bst` into a compressed QCOW2, and a binary
  SHA-256 manifest is generated beside it.

  Artifact interface for later publication (Task 3): this element's
  install-root contains exactly two files —
  `podman-vm-<fsdk-version>-<arch>.qcow2` and
  `podman-vm-<fsdk-version>-<arch>.qcow2.sha256` (`sha256sum --binary`
  output for that exact file). `<fsdk-version>` is read from the
  already-staged `/sysroot/etc/os-release`'s `VERSION_ID` (the FSDK
  Flatpak-runtime branch, e.g. "25.08") rather than the Justfile's
  git-describe parse of `elements/freedesktop-sdk.bst` (`fsdk_version`,
  e.g. "25.08.14") used for the OCI images' labels/tags at `just export`
  time — this element has no shell access to that file outside the
  sandbox, and both values derive from the same pinned junction ref. See
  docs/skills/vm-podman-guest.md for the full rationale and the precision gap
  this leaves for Task 3 to reconcile if a point-release-exact name is
  ever required.

build-depends:
- freedesktop-sdk.bst:components/fakecap.bst
- freedesktop-sdk.bst:vm/deploy-tools.bst
- freedesktop-sdk.bst:vm/prepare-image.bst
- podman-vm/podman-vm-initial-scripts.bst
- filename: podman-vm/podman-vm-filesystem.bst
  config:
    location: '/sysroot'
- filename: freedesktop-sdk.bst:vm/boot/efi.bst
  config:
    location: '/sysroot/efi'
# Staged out-of-root to avoid any overlap risk with vm/deploy-tools.bst's
# own glibc/runtime closure at "/" (see "Configure dependency staging
# location" in BuildStream's docs) — invoked below by full path instead of
# relying on PATH.
- filename: qemu-img/qemu-img-stack.bst
  config:
    location: '/opt/qemu-img'

environment:
  E2FSPROGS_FAKE_TIME: '%{source-date-epoch}'
  LD_PRELOAD: /usr/libexec/fakecap/fakecap.so
  FAKECAP_DB: /fakecap

variables:
  # `source-date-epoch` is freedesktop-sdk.bst's own project-scoped
  # variable (its project.conf sets it to a fixed reproducible-build
  # epoch and mirrors it into the SOURCE_DATE_EPOCH environment
  # variable); it is not visible in this project. This project's own
  # BuildStream core builtin default already exports the SOURCE_DATE_EPOCH
  # *environment* variable (used unquoted by name in the genimage.cfg
  # heredoc below) with value 1321009871 — the same value is declared here
  # as a plain variable so E2FSPROGS_FAKE_TIME (a %{} substitution, not a
  # shell expansion) can reference it too, keeping both in sync.
  source-date-epoch: '1321009871'

  # Fixed namespace UUID for THIS artifact's identity (not a per-build
  # random seed), so the assembled disk's partition/disk UUIDs are
  # byte-for-byte reproducible across rebuilds of identical content. This
  # is independent of the VM's *runtime* identity: Cloud-init's NoCloud
  # datasource supplies a fresh Lima instance-id at every boot regardless
  # of this build-time seed. Derived once, non-secret, reproducible from
  # the command alone:
  #   uuidgen -s --namespace @url \
  #     --name "https://github.com/projectbluefin/fsdk-containers/podman-vm"
  uuidnamespace: 4cff3586-cb73-555e-aad2-8e3e9a23a69c
  build-root: /genimage

  # GPT Discoverable-Partition-Spec "Linux root" type GUIDs (x86-64 /
  # arm64). Hardcoded rather than referencing freedesktop-sdk.bst's own
  # %{linux-root} (elements/include/arch.yml): that variable is scoped to
  # FSDK's own project and is not visible from this project's YAML, unlike
  # the identical heredoc inside FSDK's own vm/minimal/efi.bst, which
  # resolves it locally. Values copied verbatim from that same file.
  linux-root: 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
  (?):
  - arch == "aarch64":
      linux-root: B921B045-1DF0-41C3-AF44-4C6F280D3FAE

config:
  commands:
  - mkdir -p /fakecap
  - mkdir -p %{build-root}
  - |
    prepare-image.sh \
       --sysroot /sysroot \
       --seed "%{uuidnamespace}" \
       --rootpasswd "root" > "%{build-root}/vars"

  - |
    efi_part_uuid="$(uuidgen -s --namespace "%{uuidnamespace}" --name partition-efi)"
    root_part_uuid="$(uuidgen -s --namespace "%{uuidnamespace}" --name partition-root)"
    disk_uuid="$(uuidgen -s --namespace "%{uuidnamespace}" --name disk)"
    hash_seed="$(uuidgen -s --namespace "%{uuidnamespace}" --name hash-seed)"
    . "%{build-root}/vars"
    cat > "%{build-root}/genimage.cfg" <<EOF
    image efi.img {
        vfat {
            extraargs = "--invariant -F32 -i${id_efi} -n EFI"
        }
        mountpoint = "/efi"
        size = 105%
        temporary = true
    }
    image root.img {
        ext4  {
            label = "root"
            extraargs = "-U ${uuid_root} -E hash_seed=${hash_seed}"
            use-mke2fs = true
            fs-timestamp = "${SOURCE_DATE_EPOCH}"
        }
        size = 110%
        temporary = true
    }
    image disk.img {
        hdimage {
            align = 1M
            partition-table-type = "gpt"
            disk-uuid = "${disk_uuid}"
        }
        partition efi {
            image = "efi.img"
            partition-type-uuid = "U"
            partition-uuid = "${efi_part_uuid}"
        }
        partition root {
            image = "root.img"
            partition-type-uuid = "%{linux-root}"
            partition-uuid = "${root_part_uuid}"
        }
    }
    config {
      tmppath = "%{build-root}/tmp"
      outputpath = "%{build-root}"
    }
    EOF

  - du -h --max-depth=3 /sysroot | grep '^[^0]' | sort -rh
  - genimage --config "%{build-root}/genimage.cfg" --rootpath /sysroot
  - du -BM "%{build-root}/disk.img"

  - |
    fsdk_version="$(. /sysroot/etc/os-release && echo "${VERSION_ID}")"
    qcow2_name="podman-vm-${fsdk_version}-%{arch}.qcow2"
    /opt/qemu-img/usr/bin/qemu-img convert -f raw -O qcow2 -o compat=1.1 \
      "%{build-root}/disk.img" "%{install-root}/${qcow2_name}"
    cd "%{install-root}"
    du -BM "${qcow2_name}"
    sha256sum --binary "${qcow2_name}" > "${qcow2_name}.sha256"
    cat "${qcow2_name}.sha256"

# DO NOT EDIT. Generated from catalog/buildah.yaml by
# scripts/generate_image_elements.py (oci).
# Change the record, then run: just catalog-write

kind: script

build-depends:
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  - freedesktop-sdk.bst:components/oci-builder.bst
  - base/base-init-script.bst
  - filename: buildah/buildah-runtime.bst
    config:
      location: /layer

variables:
  (@):
    - include/slim.yml
    - include/fsdk-version.yml

config:
  commands:
    - "%{slim-distroless-commands}"
    - |
      rm -rf /layer/usr/share/misc/magic.mgc /layer/usr/libexec/podman/aardvark-dns \
        /layer/usr/share/bash-completion
      rm -f /layer/usr/bin/{addpart,agetty,bits,blkdiscard,blkid,blkpr,blkzone} \
        /layer/usr/bin/{blockdev,cal,capsh,cfdisk,chcpu,chmem,choom,chrt,col} \
        /layer/usr/bin/{colcrt,colrm,column,copyfilerange,coresched,ctrlaltdel} \
        /layer/usr/bin/{delpart,dmesg,dumpsexp,eject,enosys,exch,fadvise} \
        /layer/usr/bin/{fallocate,fdisk,file,filecap,fincore,findfs,findmnt} \
        /layer/usr/bin/{flock,fsck,fsck.cramfs,fsck.minix,fsfreeze,fstrim} \
        /layer/usr/bin/{getcap,getino,getopt,getpcaps,hardlink,hexdump,hmac256} \
        /layer/usr/bin/{hwclock,i386,ionice,ipcmk,ipcrm,ipcs,irqtop,isosize} \
        /layer/usr/bin/{last,lastb,lastlog2,ldattach,linux32,linux64,logger} \
        /layer/usr/bin/{look,losetup,lsblk,lsclocks,lscpu,lsfd,lsipc,lsirq} \
        /layer/usr/bin/{lslocks,lslogins,lsmem,lsns,lz4,lz4c,lz4cat,mcookie} \
        /layer/usr/bin/{mesg,mkfs,mkfs.bfs,mkfs.cramfs,mkfs.minix,mkswap,more} \
        /layer/usr/bin/{mount,mountpoint,mpicalc,namei,netcap,nsenter,partx} \
        /layer/usr/bin/{pipesz,pivot_root,prlimit,pscap,readprofile,rename} \
        /layer/usr/bin/{renice,resizepart,rev,rfkill,rtcwake,script,scriptlive} \
        /layer/usr/bin/{scriptreplay,setarch,setcap,setpgid,setpriv,setsid} \
        /layer/usr/bin/{setterm,sfdisk,sulogin,swaplabel,swapoff,swapon} \
        /layer/usr/bin/{switch_root,taskset,uclampset,ul,umount,uname26,unlz4} \
        /layer/usr/bin/{unshare,utmpdump,uuidd,uuidgen,uuidparse,waitpid,wdctl} \
        /layer/usr/bin/{whereis,wipefs,x86_64,aarch64,zramctl}
    - |
      if [ -d /initial_scripts ]; then
        for i in /initial_scripts/*; do
          "${i}" /layer
        done
      fi
    - |
      cd "%{install-root}"
      build-oci <<EOF
      mode: oci
      gzip: disabled
      images:
      - os: linux
        architecture: "%{go-arch}"
        layer: /layer
        comment: "fsdk-containers buildah image"
        config:
          Entrypoint: ['/usr/bin/buildah']
          Env: ['BUILDAH_ISOLATION=chroot']
          Labels:
            'org.opencontainers.image.title': 'buildah'
            'org.opencontainers.image.description': 'Distroless Buildah container-building tool built on freedesktop-sdk'
            'org.opencontainers.image.vendor': 'Project Bluefin'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.url': 'https://github.com/projectbluefin/fsdk-containers'
            'org.opencontainers.image.source': 'https://github.com/projectbluefin/fsdk-containers'
            'io.artifacthub.package.readme-url': 'https://raw.githubusercontent.com/projectbluefin/fsdk-containers/main/README.md'
            'io.artifacthub.package.logo-url': 'https://projectbluefin.io/logo.png'
            'io.artifacthub.package.license': 'Apache-2.0'
            'io.artifacthub.package.maintainers': '[{"name":"Project Bluefin","email":"maintainers@projectbluefin.io"}]'
            'io.artifacthub.package.keywords': 'distroless,freedesktop-sdk,bluefin,buildah'
            'io.artifacthub.package.category': 'integration-delivery'
        index-annotations:
          'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/buildah:%{fsdk-version}'
      EOF

kind: stack
description: Shared printing runtime stack for the projectbluefin printer applications.

# Everything the four printer applications (ghostscript, gutenprint, hplip, ps)
# need at runtime and nowhere else: the printing/base.bst devel stack (CUPS,
# cups-filters, libcupsfilters, libppd, ghostscript, avahi-printing, PAPPL,
# pappl-retrofit) plus the OS runtime every one of them also depends on
# (bash entrypoint, python3 for pyppd PPD archives and HPLIP, CA certs,
# tzdata). printing/runtime-layer.bst chisels this down to runtime-only and
# printing/runtime-layer's OCI script publishes it as the shared base layer
# every printer-app image is built on top of (#342).
#
# Deliberately NOT the plain base/base-stack.bst: that stack's own OCI element
# (oci/base.bst) applies the distroless SLIM recipe, which removes bash. The
# printer appliances are not distroless (docs/skills/printing-base.md), so
# this stack takes runtime-gnu/runtime-minimal/ca-certificates/tzdata
# directly, the same way base/base-stack.bst does, and leaves bash removal to
# nobody: include/slim-printing.yml keeps it on purpose.
depends:
- freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
- freedesktop-sdk.bst:components/ca-certificates.bst
- freedesktop-sdk.bst:components/tzdata.bst
- freedesktop-sdk.bst:components/python3.bst
- freedesktop-sdk.bst:integration/extra-fs.bst
- freedesktop-sdk.bst:integration/ldconfig.bst
- printing/base.bst

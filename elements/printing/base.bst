kind: stack
description: Shared printing base for the projectbluefin printer applications (devel).

# The one CUPS provider for every printer application: CUPS, cups-filters,
# libcupsfilters, libppd, ghostscript, mutool, the nonroot avahi-daemon, and
# PAPPL + pappl-retrofit. The CUPS/avahi/ghostscript customizations come from
# patches/freedesktop-sdk/0002-printing-*.patch.
#
# This is a build-time stack: its artifacts keep every split domain (devel
# headers, .pc files, ...). Consumers build-depend on it and compose their
# final image from runtime domains only. Consumer contract:
# docs/skills/printing-base.md.
depends:
- freedesktop-sdk.bst:components/avahi-printing.bst
- freedesktop-sdk.bst:components/cups-daemon-only.bst
- freedesktop-sdk.bst:components/cups-filters.bst
- freedesktop-sdk.bst:components/ghostscript.bst
- freedesktop-sdk.bst:components/libcupsfilters.bst
- freedesktop-sdk.bst:components/libppd.bst
- freedesktop-sdk.bst:components/mutool.bst
- printing/pappl.bst
- printing/pappl-retrofit.bst

# BusyBox 1.38.0 distribution and linked-input notice

The distributed `busybox` is built from the tracked complete BusyBox 1.38.0
source archive and complete resolved `busybox.config`. BusyBox states that
this release is GPL version 2 only; `busybox-LICENSE.txt` preserves that
license. Keeping the exact source archive and build configuration beside this
recipe supplies the corresponding source used for the executable.

BusyBox includes a lightly modified bzip2 1.0.4 implementation. Its notice is
preserved in `busybox-bzip2-LICENSE.txt`. Additional permissive notices,
including the yescrypt component notices, remain verbatim in the tracked
complete source archive. The recipe does not replace or suppress those source
notices.

`archive-inventory.tsv` records every static archive observed in the final
link, distinguishing source-built BusyBox archives from locked Alpine builder
archives. Each row supplies package, version, license, retained license
material, and source evidence. The build rejects missing, extra, or differently
owned archives. This inventory is factual distribution evidence, not a legal
conclusion.

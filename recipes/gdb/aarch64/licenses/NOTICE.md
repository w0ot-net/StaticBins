# GDB 17.2 distribution notice

`artifacts/aarch64/gdb` and the matching container image are built from the exact
archive recorded in `../source.lock`. That archive is mirrored in this
repository's immutable `gdb-17.2-source` release; the official GNU URL remains
the authoritative upstream location and checksum-equivalent fallback.

GDB and the libraries built from its source tree are covered by the license
notices in that source archive. The unmodified top-level GNU license texts are
included here as `GDB-COPYING*.txt`.

`archive-inventory.tsv` is a factual record of every external static archive
expected in the final link. It records the exact package/version in the locked
builder, Alpine's declared license, the corresponding license material in this
directory, and the immutable Alpine `APKBUILD` that identifies the upstream
source. The build reconciles its linker map against this inventory and fails on
an extra, missing, or differently owned archive.

This inventory documents provenance and the materials distributed with the
binary; it is not a legal conclusion about license compatibility.

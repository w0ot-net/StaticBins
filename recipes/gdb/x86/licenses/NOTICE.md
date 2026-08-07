# GDB 17.2 distribution notice

`artifacts/x86/gdb` is built from the exact archive recorded in
`../source.lock` and retained at `../sources/gdb-17.2.tar.xz`. The official GNU
URL in the lock records its upstream provenance; the committed copy is the
normal build input.

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

The linked-input package versions were validated against builder
`ghcr.io/w0ot-net/static_bins-builder@sha256:d1b88e0a419c7e778d59404534c4da0288f6b874830eb58e9e854d0aebeb99ab`.

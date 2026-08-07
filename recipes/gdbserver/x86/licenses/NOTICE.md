# GDBserver 16.3 distribution notice

`artifacts/x86/gdbserver` is built from the exact archive recorded in
`../source.lock` and retained at `../sources/gdb-16.3.tar.xz`. The official GNU
URL in the lock records its upstream provenance; the committed copy is the
normal build input.

GDBserver and the libraries built from the GDB source tree are covered by the
license notices in that source archive. The unmodified top-level GNU license
texts are included here as `GDB-COPYING*.txt`.

`archive-inventory.tsv` records every external static archive expected in the
final link, its exact package and version in the locked builder, Alpine's
declared license, copied license material, and immutable Alpine `APKBUILD`.
The build fails on an extra, missing, or differently owned linked archive.

The Alpine kernel recorded in `../vm.lock` is downloaded into a user cache and
used only to boot the functional smoke test. It is not linked into GDBserver,
copied to the artifact directory, or distributed by this repository.

This inventory documents provenance and distributed materials; it is not a
legal conclusion about license compatibility.

# ltrace 0.8.1 distribution notice

`artifacts/x86/ltrace` is built from the exact archive recorded in
`../source.lock` and retained at `../sources/ltrace-0.8.1.tar.gz`. The official
GitLab URL in the lock records its upstream provenance; the committed copy is
the normal build input. ltrace is licensed under GPL-2.0-or-later, and its
unmodified license text is included as `ltrace-COPYING.txt`.

`archive-inventory.tsv` records every external static archive expected in the
final link, including the exact package/version, Alpine's declared license,
reviewed license material, and the immutable Alpine `APKBUILD` identifying the
upstream source. The build reconciles its linker map against this inventory and
fails on an extra, missing, or differently owned archive.

The elfutils, GCC runtime, musl, zlib, and zstd license materials are included
here. This inventory documents provenance and distribution materials; it is
not a legal conclusion about license compatibility.

The linked-input package versions were validated against builder
`ghcr.io/w0ot-net/static_bins-builder@sha256:65e48b9e73e91b0bcca1bb7d876e0e4dae4943626834c579121cba5b203aa568`.

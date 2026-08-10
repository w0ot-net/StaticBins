# bpftrace 0.26.1 distribution notice

`artifacts/aarch64/bpftrace` is built from the exact archive recorded in
`../source.lock` and retained at `../sources/bpftrace-0.26.1.tar.gz`. The
official GitHub URL in the lock records its upstream provenance; the committed
copy is the normal build input. bpftrace is licensed under Apache-2.0, and its
unmodified license text is included as `bpftrace-LICENSE.txt`.

`archive-inventory.tsv` records every reviewed external static-archive family
expected in the final link, including exact package/version ownership,
Alpine's declared license, reviewed license material, and the immutable Alpine
`APKBUILD` identifying upstream source. The build reconciles every archive in
the final linker map against that inventory and fails on an extra, absent,
ambiguously matched, or differently owned archive. `header-inputs.tsv`
separately records the linked cereal template input.

The distributed executable is compressed by unmodified Alpine UPX 5.2.0.
UPX's decompressor stub is embedded in the artifact, so `packed-inputs.tsv`,
`UPX-LICENSE.txt`, and `UPX-COPYING.txt` record its provenance and special
exception for compressed executables. `upx -t` validates the result during the
build, and users may recover the larger validated payload with `upx -d`.

License materials for BCC, libbpf, bzip2, elfutils, GCC runtime libraries,
musl, xz, zlib, zstd, LLVM, Clang, cereal, and UPX are included here. This
inventory documents provenance and distribution materials; it is not a legal
conclusion about license compatibility.

The linked-input package versions were validated against builder
`ghcr.io/w0ot-net/static_bins-builder@sha256:532b10c8167fb75119a17ee27c7a49dd2644a7e1782322b3f4faab805d4a0406`.

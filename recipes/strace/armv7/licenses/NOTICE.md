# strace 6.16 distribution notice

`artifacts/armv7/strace` is built from the exact official archive retained at
`../sources/strace-6.16.tar.xz` and locked in `../source.lock`. Upstream also
publishes `https://strace.io/files/6.16/strace-6.16.tar.xz.asc`, but this recipe
has not adopted a signer key backed by authenticated official full-fingerprint
evidence. It deliberately declares the weaker `checksum-only` authentication
mode and does not attempt PGP verification or fall back after a failed check.

strace is distributed under LGPL-2.1-or-later. Its project notice and license
are retained as `strace-COPYING.txt` and `strace-LGPL-2.1-or-later.txt`. The
build deliberately uses the release's bundled Linux UAPI headers; their
GPL-2.0-only text and Linux syscall exception are retained as
`linux-uapi-GPL-2.0.txt`, `linux-uapi-Linux-syscall-note.txt`, and the related
`linux-uapi-COPYING.txt` notice.

`archive-inventory.tsv` records every external static archive expected in the
final link, its exact package and version in the locked builder, Alpine's
declared license, copied upstream license material, and immutable Alpine
`APKBUILD`. The build fails on an extra, missing, or differently owned linked
archive. Internal `libstrace.a` is attributed to the accepted strace source.

This inventory documents provenance and distributed materials; it is not a
legal conclusion about license compatibility.

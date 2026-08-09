# GNU Netcat 0.7.1 distribution notice

`artifacts/x86_64/nc` is built from the exact signed archive recorded in
`../source.lock` and retained under `../sources/`. GNU Netcat is licensed
under GPL-2.0-or-later; the unmodified upstream license is included as
`netcat-COPYING.txt`.

The checksum-locked patch under `../patches/` is a repository-reviewed local
correctness fix for the released Linux packet-info code. It changes only two
address-copy lengths and is not separately authenticated upstream source.

`archive-inventory.tsv` records every external static archive expected in the
final link, including package/version, Alpine's declared license, reviewed
license material, and immutable aports source evidence. The build reconciles
the linker map exactly and fails on an extra, missing, or differently owned
archive.

The linked-input package versions were validated against builder
`ghcr.io/w0ot-net/static_bins-builder@sha256:f82e33360719a8e68dfd83ad174a7c18574cdb8ee4f7da5b416be3bf62fdbd47`. This inventory is factual distribution evidence, not a legal
conclusion.

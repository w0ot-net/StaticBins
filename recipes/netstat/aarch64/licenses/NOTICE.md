# net-tools 2.10 netstat distribution notice

`artifacts/aarch64/netstat` is built from the exact archive recorded in
`../source.lock` and retained under `../sources/`. net-tools is licensed under
GPL-2.0-or-later; the unmodified upstream license is included as
`net-tools-COPYING.txt`.

The checksum-locked patch under `../patches/` is copied from an immutable
Alpine aports revision and links to the upstream discussion. It corrects only
the released `%Lu` interface-counter parsing and is reviewed downstream
evidence, not an authenticated signature over the upstream release archive.

`archive-inventory.tsv` records the source-built net-tools library and every
builder-owned static archive expected in the final link, including package,
version, license material, and source evidence. The build reconciles the
linker map exactly and fails on an extra, missing, or differently owned
archive.

The linked-input package versions were validated against builder
`ghcr.io/w0ot-net/static_bins-builder@sha256:ad08678e77f05a97fe00b7dd0fc67c47aa4c7ec3ad903a0e826e4f1eb69b4a00`.
This inventory is factual distribution evidence, not a legal conclusion.

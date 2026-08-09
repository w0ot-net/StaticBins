# rsync 3.4.4 distribution notice

`artifacts/armv7/rsync` is built from the exact signed archive recorded in
`../source.lock` and retained under `../sources/`. rsync is licensed under
GPL-3.0-or-later; the unmodified upstream license is included as
`rsync-COPYING.txt`.

The selected build links bundled popt and zlib object files directly rather
than creating source-built archives. `bundled-object-inventory.tsv` records
and validates each of those final-link inputs against the signed rsync archive,
the bundled popt MIT-style terms, and the zlib notice. `archive-inventory.tsv`
separately reconciles every builder-owned static archive observed in the final
linker map with exact package, version, license, and source evidence.

The linked-input package versions were validated against builder
`ghcr.io/w0ot-net/static_bins-builder@sha256:a197c59a45f7fb1683437dd6a4fc1939f010f9cb4606cc64222d966c4341b7c4`.
This inventory is factual distribution evidence, not a legal conclusion.

# Dropbear 2026.94 distribution and linked-input notice

`artifacts/armv7/dropbearmulti` is built from the exact signed archive
recorded in `../source.lock` and retained under `../sources/`. The upstream
`dropbear-LICENSE.txt` preserves Dropbear's consolidated permissive terms and
component notices, including the Dropbear, OpenSSH-derived, PuTTY-derived, and
public-domain code used by the selected programs.

The build links the release's bundled libtomcrypt 1.18.2 and libtommath 1.2.0
archives. Their license texts are retained separately.
`archive-inventory.tsv` reconciles those source-built archives and every
builder-owned static archive observed in the final linker map with exact
package, version, license, and source evidence.

The linked-input package versions were validated against builder
`ghcr.io/w0ot-net/static_bins-builder@sha256:a197c59a45f7fb1683437dd6a4fc1939f010f9cb4606cc64222d966c4341b7c4`.
This inventory is factual distribution evidence, not a legal conclusion.

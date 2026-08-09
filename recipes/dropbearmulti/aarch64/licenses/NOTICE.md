# Dropbear 2026.94 distribution and linked-input notice

`artifacts/aarch64/dropbearmulti` is built from the exact signed archive
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
`ghcr.io/w0ot-net/static_bins-builder@sha256:ad08678e77f05a97fe00b7dd0fc67c47aa4c7ec3ad903a0e826e4f1eb69b4a00`.
This inventory is factual distribution evidence, not a legal conclusion.

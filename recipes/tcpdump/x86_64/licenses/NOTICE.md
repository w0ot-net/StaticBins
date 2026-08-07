# tcpdump 4.99.4 distribution notice

`artifacts/x86_64/tcpdump` is built from the exact tcpdump 4.99.4 and libpcap
1.10.4 archives recorded in `../source.lock`. The accepted copies are retained
under `../sources/`; the official tcpdump.org URLs in the lock record their
upstream provenance, while the committed copies are the normal build inputs.

The unmodified upstream `LICENSE` files from those exact archives are included
here as `tcpdump-LICENSE.txt` and `libpcap-LICENSE.txt`. The locked x86-64
builder is
`ghcr.io/w0ot-net/static_bins-builder@sha256:fb44acd90b9d6b70c0822ccca6e9d7c29018980d6c2e9b0cd50674637ce69e54`.

`archive-inventory.tsv` is a factual record of every static archive observed in
the final link. The two project-built archives map to their locked upstream
source. External rows record the exact package/version in the builder, Alpine's
declared license, the copied distribution material, and the immutable Alpine
`APKBUILD` identifying its upstream source. The build fails on an extra,
missing, differently owned, or differently licensed archive.

This inventory documents provenance and the materials distributed with the
binary; it is not a legal conclusion about license compatibility.

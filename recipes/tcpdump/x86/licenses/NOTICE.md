# tcpdump 4.99.4 distribution notice

`artifacts/x86/tcpdump` is built from the exact tcpdump 4.99.4 and libpcap
1.10.4 archives recorded in `../source.lock`. The accepted copies are retained
under `../sources/`; the official tcpdump.org URLs in the lock record their
upstream provenance, while the committed copies are the normal build inputs.

The unmodified upstream `LICENSE` files from those exact archives are included
here as `tcpdump-LICENSE.txt` and `libpcap-LICENSE.txt`. The locked 32-bit x86
builder is
`ghcr.io/w0ot-net/static_bins-builder@sha256:d1b88e0a419c7e778d59404534c4da0288f6b874830eb58e9e854d0aebeb99ab`.

`archive-inventory.tsv` is a factual record of every static archive observed in
the final link. The two project-built archives map to their locked upstream
source. External rows record the exact package/version in the builder, Alpine's
declared license, the copied distribution material, and the immutable Alpine
`APKBUILD` identifying its upstream source. The build fails on an extra,
missing, differently owned, or differently licensed archive.

This inventory documents provenance and the materials distributed with the
binary; it is not a legal conclusion about license compatibility.

# curl 8.21.0 distribution notice

`artifacts/armv7/curl` is built from the exact signed curl archive recorded
in `../source.lock` and retained under `../sources/`. The curl license is
included as `curl-COPYING.txt`.

The selected static build links the source-built libcurl archive with the
locked builder's LibreSSL, zlib, musl, and GCC runtime archives.
`archive-inventory.tsv` reconciles every archive observed in the final linker
map with its package, version, license text, and source evidence. The linked
package versions are checked against the immutable ARMv7 builder digest.

This inventory is factual distribution evidence, not a legal conclusion.

# lsof 4.99.5 distribution notice

`artifacts/armv7/lsof` is built from the exact archive recorded in
`../source.lock` and retained at `../sources/lsof-4.99.5.tar.gz`. The official
GitHub release URL records provenance, but no detached upstream signature has
been adopted. The source therefore has the explicit weaker `checksum-only`
authentication level.

lsof is distributed under the project notice copied unchanged as
`lsof-COPYING.txt` from the accepted archive.

`archive-inventory.tsv` records every external static archive expected in the
final link, its exact package and version in the locked builder, Alpine's
declared license, copied upstream license material, and immutable Alpine
`APKBUILD`. The selected `libtirpc-nokrb.a` retains RPC support without pulling
unavailable static Kerberos/GSS dependencies. The build fails on an extra,
missing, or differently owned linked archive.

This inventory documents provenance and distributed materials; it is not a
legal conclusion about license compatibility.

# socat 1.8.1.3 distribution notice

`artifacts/armv7/socat` is built from a deterministic archive retained at
`../sources/socat-1.8.1.3.tar`. The archive was produced from the official
HTTPS Git repository with:

```sh
git archive --format=tar --prefix=socat-1.8.1.3/ \
    12c08bf66d709fba17035ce95d85bd218428d9ba
```

The lightweight `tag-1.8.1.3` tag was required to resolve to that exact
commit. It has no upstream signature, so the source has the explicit weaker
`checksum-only` authentication level recorded in `../source.lock`. Normal
builds use only the tracked, checksum-locked archive and do not access Git.
The build exports `SOURCE_DATE_EPOCH=1782453234`, the accepted commit's exact
timestamp, so socat's compiled version banner does not depend on build time.

socat's GPL-2.0-only text is retained as `socat-COPYING.txt`, together with
the upstream `socat-COPYING.OpenSSL.txt` exception material. The distributed
executable is linked with Alpine's LibreSSL 4.3.1 static libraries, whose
BSD/ISC notices are retained as `LibreSSL-COPYING.txt`; it does not contain
the Apache-2.0 OpenSSL 3 libraries.

`archive-inventory.tsv` records every external static archive expected in the
final link, its exact package and version in the locked builder, Alpine's
declared license, copied upstream license material, and immutable Alpine
`APKBUILD`. The build fails on an extra, missing, or differently owned linked
archive.

This inventory documents provenance and distributed materials; it is not a
legal conclusion about license compatibility.

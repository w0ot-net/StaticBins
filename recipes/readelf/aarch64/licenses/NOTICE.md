# GNU readelf 2.47 distribution notice

`artifacts/aarch64/readelf` is built from the exact signed GNU Binutils archive
recorded in `../source.lock` and retained under `../sources/`. The readelf and
SFrame code selected by this build is distributed under
GPL-3.0-or-later; the unmodified upstream GPLv3 text is included as
`binutils-COPYING3.txt`. The separately licensed libiberty text is retained as
`libiberty-COPYING.LIB.txt` when that archive enters the final link.

`archive-inventory.tsv` reconciles every archive in the final linker maps for
the Binutils programs built in the cacheable compile stage. Source-built rows refer
to the tracked signed release; builder rows record exact APK ownership,
versions, licenses, reviewed license texts, and immutable aports evidence.

Only readelf crosses the recipe's artifact boundary. Temporary sibling tools
exist solely to make the common Binutils compile layer reusable by their own
independent recipes. This inventory is factual distribution evidence, not a
legal conclusion.

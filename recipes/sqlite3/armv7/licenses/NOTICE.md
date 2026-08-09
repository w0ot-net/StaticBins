# SQLite 3.53.4 distribution notice

`artifacts/armv7/sqlite3` is built from the exact official SQLite amalgamation
archive recorded in `../source.lock` and retained under `../sources/`. SQLite's
deliverable code is dedicated to the public domain; its blessing is included
as `SQLite-blessing.txt`.

The build directly compiles only `shell.c` and `sqlite3.c`, so the differently
licensed configure and Tcl scaffolding retained inside the complete upstream
archive does not enter the executable. `archive-inventory.tsv` reconciles all
builder-owned static archives observed in the final link with exact package,
version, license, and source evidence.

SQLite publishes an official SHA3-256 for this archive but no detached release
signature. The official published SHA3-256 at intake was
`454e45f61c6bd75b7420e7190732dea03ce6639c63ada47bbc592f67fc340338`;
normal builds verify the committed bytes with the repository's SHA-256 lock
and report the
checksum-only assurance level. This inventory is factual distribution
evidence, not a legal conclusion.

# Static SQLite 3.53.4 CLI for ARMv7

From the repository root, run:

```sh
./build.sh sqlite3 armv7
```

The command requires Bash, Docker, Docker Buildx, `file`, `readelf`, and
`sha256sum`. It automatically pulls the public immutable ARMv7 builder
recorded in `builders/armv7/environment.lock`; it fetches no source or build
packages. The artifact is replaced only after complete validation.

The CLI includes JSON, FTS5 full-text search, RTree, dbstat/dbpage inspection,
the `.recover` command, math functions, and explanatory query-plan comments.
Dynamic extension loading and external readline/editline integration are
omitted, keeping the executable standalone
and avoiding runtime modules or terminal databases. Ordinary SQLite database,
dump, backup, recovery, integrity-check, and interactive shell behavior remain
available.

The official download page publishes a SHA3-256 for the accepted amalgamation
archive but no detached release signature, so source authentication is
explicitly checksum-only. SQLite's deliverable source is dedicated to the
public domain.

The output is a stripped ARMv7 hard-float static PIE with no interpreter, shared
dependencies, or text relocations. Its target smoke test exercises
`.recover`, JSON, FTS5, RTree, math, integrity checking, and a real database
backup.

# static_bins

Ready-to-run static Linux utilities with small, documented, repeatable build
recipes.

| Architecture | Committed artifacts | Rebuild support |
| --- | --- | --- |
| AArch64 | GDB 17.2 | Complete recipe |
| x86-64 | tcpdump 4.99.4; `gdbserver`, `lsof`, `socat`, `strace` | tcpdump recipe; four legacy artifacts |

## Build

List the enabled recipes, then build one with Bash and Docker:

```sh
./build.sh list
./build.sh gdb
./build.sh tcpdump
```

The root command reads the minimal allowlist in `recipes/catalog.tsv` and
delegates to the matching recipe. Committed executables live in
`artifacts/<architecture>/`, tool-specific builds in
`recipes/<tool>/<architecture>/`, and locked reusable environments in
`builders/<architecture>/`. Each supported recipe also retains its exact,
checksum-locked upstream archives under `sources/`, so an ordinary build does
not depend on an upstream source URL.

See the recipe README for
[GDB](recipes/gdb/aarch64/README.md) or
[tcpdump](recipes/tcpdump/x86_64/README.md) for prerequisites, source and
feature policy, direct commands, and output details.

## Containers

Published images include:

- `ghcr.io/w0ot-net/static_bins-gdb:17.2-aarch64`
- `ghcr.io/w0ot-net/static_bins-gdb:aarch64-latest`
- `ghcr.io/w0ot-net/static_bins-tcpdump:4.99.4-x86_64`
- `ghcr.io/w0ot-net/static_bins-tcpdump:x86_64-latest`
- `ghcr.io/w0ot-net/static_bins-builder:aarch64-alpine-3.24.1-r1`
- `ghcr.io/w0ot-net/static_bins-builder:x64-alpine-3.24.1-r1`

The `x64-*` builder names are retained public compatibility identifiers; the
repository uses `x86_64` internally. Normal builds use the immutable builder
digest committed under `builders/<architecture>/environment.lock` and never
resolve packages or silently fall back to another image.

Builder publication is a separate maintainer operation. Candidate builders can
be validated with `./builders/aarch64/build.sh` or
`./builders/x86_64/build.sh`; start the locked AArch64 environment with
`./builders/aarch64/run.sh`.

See [`doc/adding-a-binary.md`](doc/adding-a-binary.md) for the recipe contract
and [`AGENTS.md`](AGENTS.md) for repository-wide build and validation rules.

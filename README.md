# static_bins

Ready-to-run static Linux utilities with small, documented, repeatable build
recipes.

| Architecture | Ready-to-run binaries | Rebuild support |
| --- | --- | --- |
| AArch64 | [GDB 17.2](artifacts/aarch64/gdb); [GDBserver 16.3](artifacts/aarch64/gdbserver); [lsof 4.99.5](artifacts/aarch64/lsof); [socat 1.8.1.3](artifacts/aarch64/socat) | [GDB](recipes/gdb/aarch64/README.md); [GDBserver](recipes/gdbserver/aarch64/README.md); [lsof](recipes/lsof/aarch64/README.md); [socat](recipes/socat/aarch64/README.md) |
| x86-64 | [tcpdump 4.99.4](artifacts/x86_64/tcpdump); [GDBserver 16.3](artifacts/x86_64/gdbserver); [lsof 4.99.5](artifacts/x86_64/lsof); [socat 1.8.1.3](artifacts/x86_64/socat); [strace](artifacts/x86_64/strace) | [tcpdump](recipes/tcpdump/x86_64/README.md); [GDBserver](recipes/gdbserver/x86_64/README.md); [lsof](recipes/lsof/x86_64/README.md); [socat](recipes/socat/x86_64/README.md); one legacy artifact |

Clone the repository or follow an artifact link to obtain the standalone
executable. GHCR is not used to distribute utility binaries.

## Verify

Check all files against the committed integrity manifest:

```sh
sha256sum -c artifacts/SHA256SUMS
```

Only artifacts explicitly marked `Exact rebuild + GitHub attestation` have
build provenance. See [`TRUST.md`](TRUST.md) for current per-file status and the
GitHub CLI verification command.

## Build

List the enabled recipes, then build one with Bash, Docker, and the Docker
Buildx plugin:

```sh
./build.sh list
./build.sh gdb aarch64
./build.sh gdbserver aarch64
./build.sh lsof x86_64
./build.sh socat aarch64
./build.sh tcpdump x86_64
```

The root command reads the minimal allowlist in `recipes/catalog.tsv` and
delegates to the matching tool/architecture recipe. The architecture may be
omitted only when a tool has exactly one catalog row. Committed executables
live in `artifacts/<architecture>/`, tool-specific builds in
`recipes/<tool>/<architecture>/`, and locked reusable environments in
`builders/<architecture>/`. Each supported recipe also retains its exact,
checksum-locked upstream archives under `sources/`, so an ordinary build does
not depend on an upstream source URL.

See the recipe README for
[GDB](recipes/gdb/aarch64/README.md) or
[tcpdump](recipes/tcpdump/x86_64/README.md), or the architecture-specific
[GDBserver](recipes/gdbserver/), [lsof](recipes/lsof/), and
[socat](recipes/socat/) recipes for prerequisites, source and feature policy,
direct commands, and output details.

## Builder images

GHCR publishes reusable build environments only:

- `ghcr.io/w0ot-net/static_bins-builder:aarch64-alpine-3.24.1-r2`
- `ghcr.io/w0ot-net/static_bins-builder:armv7-alpine-3.24.1-r1`
- `ghcr.io/w0ot-net/static_bins-builder:x64-alpine-3.24.1-r2`

The `x64-*` builder names are retained public compatibility identifiers; the
repository uses `x86_64` internally. The internal `armv7` identifier maps to
OCI platform `linux/arm/v7`. Normal builds use the immutable builder digest
committed under `builders/<architecture>/environment.lock` and never resolve
packages or silently fall back to another image.

Builder publication is a separate maintainer operation. Candidate builders can
be validated with `./builders/aarch64/build.sh`, `./builders/armv7/build.sh`, or
`./builders/x86_64/build.sh`; start the locked AArch64 environment with
`./builders/aarch64/run.sh`. Candidate builder validation also requires Docker
Buildx. Repository CI validates recipes but does not publish utility images.

See [`doc/adding-a-binary.md`](doc/adding-a-binary.md) for the recipe contract.
The broader documentation map and system architecture start at
[`doc/README.md`](doc/README.md).
Repository-wide build and validation rules are in
[`AGENTS.md`](AGENTS.md).

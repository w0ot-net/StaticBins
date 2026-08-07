# static_bins

Ready-to-run static Linux utilities with small, documented, repeatable build
recipes.

| Architecture | Ready-to-run binaries | Rebuild support |
| --- | --- | --- |
| AArch64 | [GDB 17.2](artifacts/aarch64/gdb); [GDBserver 16.3](artifacts/aarch64/gdbserver); [lsof 4.99.5](artifacts/aarch64/lsof); [socat 1.8.1.3](artifacts/aarch64/socat); [strace 6.16](artifacts/aarch64/strace); [tcpdump 4.99.4](artifacts/aarch64/tcpdump) | [GDB](recipes/gdb/aarch64/README.md); [GDBserver](recipes/gdbserver/aarch64/README.md); [lsof](recipes/lsof/aarch64/README.md); [socat](recipes/socat/aarch64/README.md); [strace](recipes/strace/aarch64/README.md); [tcpdump](recipes/tcpdump/aarch64/README.md) |
| ARMv7 | [GDB 17.2](artifacts/armv7/gdb); [GDBserver 16.3](artifacts/armv7/gdbserver); [lsof 4.99.5](artifacts/armv7/lsof); [socat 1.8.1.3](artifacts/armv7/socat); [strace 6.16](artifacts/armv7/strace); [tcpdump 4.99.4](artifacts/armv7/tcpdump) | [GDB](recipes/gdb/armv7/README.md); [GDBserver](recipes/gdbserver/armv7/README.md); [lsof](recipes/lsof/armv7/README.md); [socat](recipes/socat/armv7/README.md); [strace](recipes/strace/armv7/README.md); [tcpdump](recipes/tcpdump/armv7/README.md) |
| x86 | [GDB 17.2](artifacts/x86/gdb); [GDBserver 16.3](artifacts/x86/gdbserver); [lsof 4.99.5](artifacts/x86/lsof); [socat 1.8.1.3](artifacts/x86/socat); [strace 6.16](artifacts/x86/strace); [tcpdump 4.99.4](artifacts/x86/tcpdump) | [GDB](recipes/gdb/x86/README.md); [GDBserver](recipes/gdbserver/x86/README.md); [lsof](recipes/lsof/x86/README.md); [socat](recipes/socat/x86/README.md); [strace](recipes/strace/x86/README.md); [tcpdump](recipes/tcpdump/x86/README.md) |
| x86-64 | [GDB 17.2](artifacts/x86_64/gdb); [GDBserver 16.3](artifacts/x86_64/gdbserver); [lsof 4.99.5](artifacts/x86_64/lsof); [socat 1.8.1.3](artifacts/x86_64/socat); [strace 6.16](artifacts/x86_64/strace); [tcpdump 4.99.4](artifacts/x86_64/tcpdump) | [GDB](recipes/gdb/x86_64/README.md); [GDBserver](recipes/gdbserver/x86_64/README.md); [lsof](recipes/lsof/x86_64/README.md); [socat](recipes/socat/x86_64/README.md); [strace](recipes/strace/x86_64/README.md); [tcpdump](recipes/tcpdump/x86_64/README.md) |

Clone the repository or follow an artifact link to obtain the standalone
executable. GHCR is not used to distribute utility binaries.

## Verify

Check all files against the committed integrity manifest:

```sh
sha256sum -c artifacts/SHA256SUMS
```

Every distributed artifact has passed its committed recipe's source, static
link, ELF, architecture, and functional checks. See [`TRUST.md`](TRUST.md) for
the separate source-authentication, build-validation, and independent-evidence
records, including the historical tcpdump attestation verification command.

## Build

List the enabled recipes, then build one with Bash, Docker, and the Docker
Buildx plugin:

```sh
./build.sh list
./build.sh gdb aarch64
./build.sh gdb armv7
./build.sh gdb x86
./build.sh gdb x86_64
./build.sh gdbserver aarch64
./build.sh gdbserver armv7
./build.sh lsof armv7
./build.sh lsof x86_64
./build.sh socat aarch64
./build.sh socat armv7
./build.sh strace armv7
./build.sh strace x86_64
./build.sh tcpdump aarch64
./build.sh tcpdump armv7
./build.sh gdbserver x86
./build.sh lsof x86
./build.sh socat x86
./build.sh strace x86
./build.sh tcpdump x86
./build.sh tcpdump x86_64
```

Run the repository's fast offline checks before committing or pushing:

```sh
./validate.sh
```

The root command reads the minimal allowlist in `recipes/catalog.tsv` and
delegates to the matching tool/architecture recipe. The architecture may be
omitted only when a tool has exactly one catalog row. Committed executables
live in `artifacts/<architecture>/`, tool-specific builds in
`recipes/<tool>/<architecture>/`, and locked reusable environments in
`builders/<architecture>/`. Each supported recipe also retains its exact,
checksum-locked upstream archives under `sources/`, so an ordinary build does
not depend on an upstream source URL.

See the architecture-specific [GDB](recipes/gdb/) and
[tcpdump](recipes/tcpdump/),
[GDBserver](recipes/gdbserver/), [lsof](recipes/lsof/),
[socat](recipes/socat/), and [strace](recipes/strace/) recipes for
prerequisites, source and feature policy, direct commands, and output details.

## Builder images

GHCR publishes reusable build environments only:

- `ghcr.io/w0ot-net/static_bins-builder:aarch64-alpine-3.24.1-r2`
- `ghcr.io/w0ot-net/static_bins-builder:armv7-alpine-3.24.1-r2`
- `ghcr.io/w0ot-net/static_bins-builder:x86-alpine-3.24.1-r1`
- `ghcr.io/w0ot-net/static_bins-builder:x64-alpine-3.24.1-r3`

The `x64-*` builder names are retained public compatibility identifiers; the
repository uses `x86_64` internally. The internal `armv7` identifier maps to
OCI platform `linux/arm/v7`. Normal builds use the immutable builder digest
committed under `builders/<architecture>/environment.lock` and never resolve
packages or silently fall back to another image.

Builder publication is a separate maintainer operation. First authenticate
Docker to GHCR as `w0ot-net` using a GitHub token authorized to write packages,
then run the allowlisted local publisher:

```sh
docker login ghcr.io -u w0ot-net
./builders/publish.sh <architecture>
```

The command refuses an existing versioned tag, validates the candidate, pushes
the versioned and architecture-floating tags with SBOM and provenance, and
prints the immutable `BUILDER_IMAGE` assignment. Inspect that published digest
before committing it separately to the architecture's `environment.lock`.
Credentials remain in Docker's external configuration; the publisher accepts
no token argument. Candidate validation and publication require Docker Buildx.
Start the currently locked AArch64 environment with
`./builders/aarch64/run.sh`.

See [`doc/adding-a-binary.md`](doc/adding-a-binary.md) for the recipe contract.
See [`doc/adding-an-architecture.md`](doc/adding-an-architecture.md) to add a
new builder architecture before adding its recipes.
The broader documentation map and system architecture start at
[`doc/README.md`](doc/README.md).
Repository-wide build and validation rules are in
[`AGENTS.md`](AGENTS.md).

# static_bins

Ready-to-run static Linux utilities with small, documented, repeatable build
recipes.

| Utility | Version | AArch64 | ARMv7 | x86-64 | x86 |
| --- | --- | --- | --- | --- | --- |
| GDB | 17.2 | [Download](artifacts/aarch64/gdb) | [Download](artifacts/armv7/gdb) | [Download](artifacts/x86_64/gdb) | [Download](artifacts/x86/gdb) |
| GDBserver | 16.3 | [Download](artifacts/aarch64/gdbserver) | [Download](artifacts/armv7/gdbserver) | [Download](artifacts/x86_64/gdbserver) | [Download](artifacts/x86/gdbserver) |
| lsof | 4.99.5 | [Download](artifacts/aarch64/lsof) | [Download](artifacts/armv7/lsof) | [Download](artifacts/x86_64/lsof) | [Download](artifacts/x86/lsof) |
| socat | 1.8.1.3 | [Download](artifacts/aarch64/socat) | [Download](artifacts/armv7/socat) | [Download](artifacts/x86_64/socat) | [Download](artifacts/x86/socat) |
| strace | 6.16 | [Download](artifacts/aarch64/strace) | [Download](artifacts/armv7/strace) | [Download](artifacts/x86_64/strace) | [Download](artifacts/x86/strace) |
| tcpdump | 4.99.4 | [Download](artifacts/aarch64/tcpdump) | [Download](artifacts/armv7/tcpdump) | [Download](artifacts/x86_64/tcpdump) | [Download](artifacts/x86/tcpdump) |

Every displayed combination has a committed recipe at
`recipes/<tool>/<architecture>/` and rebuilds with
`./build.sh <tool> <architecture>`; for example, `./build.sh lsof x86_64`.

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

Start from a fresh checkout:

```sh
git clone https://github.com/w0ot-net/static_bins.git
cd static_bins
```

Ordinary recipes require Bash, a usable Docker daemon with the Buildx plugin,
and the host commands `file`, `readelf`, and `sha256sum`. A recipe README names
any additional tools it needs, such as full-system QEMU, initramfs utilities,
or a kernel downloader.

List the enabled recipes, then build one explicit tool/architecture pair:

```sh
./build.sh list
./build.sh <tool> <architecture>
./build.sh lsof x86_64
```

Normal builds anonymously pull the public builder digest committed in the
selected architecture's `environment.lock`; GHCR login and publication
credentials are only for maintainers publishing a new builder. The tracked
source bytes and authentication evidence avoid upstream source downloads, but
a cold build still needs registry access for locked images. GDBserver and
strace recipes that use full-system validation may also download their
separately pinned smoke-test kernel on first use.

For a non-native target, a recipe may run the pinned `binfmt_misc` helper with
`--privileged` when target containers cannot already execute. Docker and
BuildKit cache image content and build layers, and VM-backed recipes retain
their verified kernel in an external cache, so later builds can reuse them.
Compilation under emulation may still take more than ten minutes. See the
[build pipeline](doc/architecture/build/BUILD_PIPELINE.md) and
[build environments](doc/architecture/build/BUILD_ENVIRONMENTS.md) for the
stable execution and builder contracts.

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

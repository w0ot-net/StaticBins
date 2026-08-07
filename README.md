# static_bins

Ready-to-run static Linux utilities with scripts that make their builds easy to
repeat and audit.

| Architecture | Binaries | Rebuild support |
| --- | --- | --- |
| AArch64 | GDB 17.2 | Complete, one-command recipe |
| x86-64 | `gdbserver`, `lsof`, `socat`, `strace`, `tcpdump` | Legacy artifacts; `tcpdump` recipe included |

## Build AArch64 GDB

The host-side wrapper requires Bash and Docker. From the repository root, run:

```sh
./aarch64_alpine_build_scripts/gdb/build.sh
```

The script builds with the exact public builder digest recorded in
`aarch64_alpine_build_scripts/environment.lock` and writes the verified binary
to `aarch64_bins/gdb`. On non-ARM64 Linux hosts, it uses QEMU user-mode
emulation; if ARM64 `binfmt_misc` support is absent, it registers the pinned
helper container automatically with `--privileged`. Docker Desktop normally
provides this support already.

The recipe takes all GDB source metadata from its committed `source.lock`, tries
the repository's immutable source release before the official GNU endpoint,
and accepts only the locked checksum. It rejects output containing an ELF
interpreter or dynamic-library dependencies. Python, Guile, debuginfod,
Babeltrace, libipt, and source-highlight are disabled to keep the result
self-contained. License and linked-archive provenance are recorded in the
recipe's `licenses/NOTICE.md`. Set `BUILD_JOBS` to adjust compilation
parallelism:

```sh
BUILD_JOBS=4 ./aarch64_alpine_build_scripts/gdb/build.sh
```

## Containers

The repository publishes reusable architecture-specific builders and artifact
images:

- `ghcr.io/w0ot-net/static_bins-builder:aarch64-alpine-3.24.1-r1` is a reusable
  static-build toolchain for GDB and other binaries.
- `ghcr.io/w0ot-net/static_bins-builder:x64-alpine-3.24.1-r1` is the locked
  x86-64 toolchain for forthcoming migrated recipes.
- `ghcr.io/w0ot-net/static_bins-gdb:17.2-aarch64` contains the ready-to-run GDB
  artifact.

The builders receive architecture-specific `aarch64-latest` or `x64-latest`
tags, and the GDB artifact receives `aarch64-latest`. All are linked to this
repository via OCI metadata. Pushes to `main` publish the GDB artifact. Normal
AArch64 builds and interactive sessions use the locked builder digest and never
resolve packages or fall back to another image. Start an interactive builder with
`./aarch64_alpine_build_scripts/run-builder.sh`.

Maintainers can validate candidate builders with the matching architecture
command:

```sh
./aarch64_alpine_build_scripts/build-builder.sh
./x64_alpine_build_scripts/build-builder.sh
```

Builder publication is a separate manual workflow with an explicit
architecture choice; recipes use a new builder only after its reported digest
is committed to that architecture's `environment.lock`.

Build conventions and artifact requirements are documented in `AGENTS.md`.

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

The recipe verifies the GDB 17.2 source checksum and rejects output containing
an ELF interpreter or dynamic-library dependencies. Python, Guile, debuginfod,
Babeltrace, libipt, and source-highlight are disabled to keep the result
self-contained. Set `BUILD_JOBS` to adjust compilation parallelism:

```sh
BUILD_JOBS=4 ./aarch64_alpine_build_scripts/gdb/build.sh
```

## Containers

The repository publishes two ARM64 images:

- `ghcr.io/w0ot-net/static_bins-builder:aarch64-alpine-3.24.1-r1` is a reusable
  static-build toolchain for GDB and other binaries.
- `ghcr.io/w0ot-net/static_bins-gdb:17.2-aarch64` contains the ready-to-run GDB
  artifact.

Both also receive an `aarch64-latest` tag and are linked to this repository via
OCI metadata. Pushes to `main` publish the GDB artifact. Normal builds and
interactive sessions use the locked builder digest and never resolve packages
or fall back to another image. Start an interactive builder with
`./aarch64_alpine_build_scripts/run-builder.sh`.

Maintainers can validate a candidate builder with
`./aarch64_alpine_build_scripts/build-builder.sh`. Builder publication is a
separate manual workflow; recipes use a new builder only after its reported
digest is committed to `environment.lock`.

Build conventions and artifact requirements are documented in `AGENTS.md`.

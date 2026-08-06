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

The script builds in a pinned Alpine 3.24.1 ARM64 container and writes the
verified binary to `aarch64_bins/gdb`. On non-ARM64 Linux hosts, it uses QEMU
user-mode emulation; if ARM64 `binfmt_misc` support is absent, it registers the
pinned helper container automatically with `--privileged`. Docker Desktop
normally provides this support already.

The recipe verifies the GDB 17.2 source checksum and rejects output containing
an ELF interpreter or dynamic-library dependencies. Python, Guile, debuginfod,
Babeltrace, libipt, and source-highlight are disabled to keep the result
self-contained. Set `BUILD_JOBS` to adjust compilation parallelism:

```sh
BUILD_JOBS=4 ./aarch64_alpine_build_scripts/gdb/build.sh
```

## Containers

Pushes to `main` publish two ARM64 images:

- `ghcr.io/w0ot-net/static_bins-builder:aarch64-alpine-3.24.1` is a reusable
  static-build toolchain for GDB and other binaries.
- `ghcr.io/w0ot-net/static_bins-gdb:17.2-aarch64` contains the ready-to-run GDB
  artifact.

Both also receive an `aarch64-latest` tag and are linked to this repository
through OCI metadata. The GDB recipe prefers the published builder and falls
back to pinned Alpine for first-time bootstrapping. Start an interactive builder
with `./aarch64_alpine_build_scripts/run-builder.sh`.

GHCR creates new packages as private; after their first publication, make them
public in the package settings to allow anonymous pulls.

Build conventions and artifact requirements are documented in `AGENTS.md`.

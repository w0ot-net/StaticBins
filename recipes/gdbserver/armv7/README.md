# Static GDBserver 16.3 for ARMv7

From the repository root, run:

```sh
./build.sh gdbserver armv7
```

The command requires Bash, Docker, Docker Buildx, `curl`, `cpio`, `gzip`, and
`qemu-system-arm`. It uses the immutable ARMv7 builder in
`builders/armv7/environment.lock`, registering the pinned ARM binfmt helper
only when native container execution is unavailable. The validated output
replaces `artifacts/armv7/gdbserver`.

The recipe builds only GDBserver and required in-tree support libraries from
the tracked, checksum-locked, GNU-signed GDB 16.3 source. It disables the
in-process agent, GDB front end, binutils, Python, Guile, debuginfod,
source-highlight, simulators, shared libraries, and unrelated tools. The
result is a stripped static ELF32 little-endian ARM hard-float `ET_EXEC`
executable.

Validation checks the ELF contract and exact version, then boots a generated,
diskless QEMU `virt,highmem=off` initramfs on a Cortex-A15 CPU for a bounded
Remote Serial Protocol exchange with a real ARMv7 target. Full-system
emulation is required because QEMU user-mode does not service GDBserver's
asynchronous event loop. The Alpine
3.22.5 kernel URL and checksum are pinned in `vm.lock`; the verified 8 MB file
is cached outside the repository and the VM definition and PID 1 smoke harness
are committed with the recipe.

GDBserver does not authenticate or encrypt remote sessions; expose it only
through a trusted transport, never directly to an untrusted network.

GNU's valid release signature uses legacy DSA with SHA-1. Source and linked
archive evidence are documented in `source.lock` and `licenses/`.

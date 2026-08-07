# Static GDBserver 16.3 for x86-64

From the repository root, run:

```sh
./build.sh gdbserver x86_64
```

The command requires Bash, Docker, and Docker Buildx. It uses the immutable
x86-64 builder in `builders/x86_64/environment.lock`. The validated output
replaces `artifacts/x86_64/gdbserver`.

The recipe builds only GDBserver and required in-tree support libraries from
the tracked, checksum-locked, GNU-signed GDB 16.3 source. It disables the
in-process agent, GDB front end, binutils, Python, Guile, debuginfod,
source-highlight, simulators, shared libraries, and unrelated tools. The
result is a stripped static x86-64 `ET_EXEC` executable.

Validation checks the ELF contract, exact version, and a bounded Remote Serial
Protocol exchange with a tiny target inside an isolated container network.
GDBserver does not authenticate or encrypt remote sessions; expose it only
through a trusted transport, never directly to an untrusted network.

GNU's valid release signature uses legacy DSA with SHA-1. Source and linked
archive evidence are documented in `source.lock` and `licenses/`.

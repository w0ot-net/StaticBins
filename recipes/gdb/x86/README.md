# x86 GDB recipe

This recipe builds GDB 17.2 as a stripped static x86 executable for the
repository's i686-compatible CMOV/SSE2 baseline.
From the repository root, use the dispatcher or the direct recipe command:

```sh
./build.sh gdb x86
./recipes/gdb/x86/build.sh
```

Both commands require Bash, Docker with the Buildx plugin, and access to the
public images named by the committed environment lock. The build consumes the
exact builder digest in `builders/x86/environment.lock` and the tracked
archive under `sources/`, validates a temporary candidate, and writes
`artifacts/x86/gdb` only after every check passes. On hosts without 32-bit x86
container support it uses QEMU user-mode emulation
and may register the pinned `binfmt_misc` helper with `--privileged` when support
is absent. Set `BUILD_JOBS` to tune compilation parallelism:

```sh
BUILD_JOBS=4 ./build.sh gdb x86
```

`source.lock` owns the version, archive, checksum, official provenance URL, and
license identifier. The accepted source copy is committed under `sources/` and
is checksum-verified before extraction; a normal build does not download it.
Reviewed license material and the exact linked-archive provenance inventory are
under `licenses/` and are checked against the final static link.

With `gpgv` installed, `./validate.sh` verifies the
committed detached signature offline against full signer fingerprint
`F40ADB902B24264AA42E50BF92EDB04BFF325CF3`. The upstream signature uses legacy
DSA/SHA-1; [`TRUST.md`](../../../TRUST.md) explains what that evidence does and
does not establish.

The build rejects anything other than a stripped static ELF32 little-endian
Intel 80386 `ET_EXEC`, as well as an incomplete link inventory. Its focused
batch test loads a symbol-bearing static x86 target, confirms GDB's x86
architecture selection, resolves `static_bins_probe_value`, and evaluates its
known `0x12345678` value without using ptrace. Python, Guile, debuginfod,
Babeltrace, libipt, simulators, and source-highlight are intentionally
disabled to keep the artifact self-contained.

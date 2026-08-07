# AArch64 GDB recipe

This recipe builds GDB 17.2 as a stripped static AArch64 executable. From the
repository root, use the stable dispatcher or the direct recipe command:

```sh
./build.sh gdb aarch64
./recipes/gdb/aarch64/build.sh
```

Both commands require Bash, Docker with the Buildx plugin, and access to the
public images named by the committed environment lock. The build consumes the
exact builder digest in `builders/aarch64/environment.lock` and the tracked
archive under `sources/`, validates a temporary candidate, and writes
`artifacts/aarch64/gdb` only after every check passes. On non-AArch64 Linux
hosts it uses QEMU user-mode emulation
and may register the pinned `binfmt_misc` helper with `--privileged` when support
is absent. Set `BUILD_JOBS` to tune compilation parallelism:

```sh
BUILD_JOBS=4 ./build.sh gdb aarch64
```

`source.lock` owns the version, archive, checksum, official provenance URL, and
license identifier. The accepted source copy is committed under `sources/` and
is checksum-verified before extraction; a normal build does not download it.
Reviewed license material and the exact linked-archive provenance inventory are
under `licenses/` and are checked against the final static link.

With `gpgv` installed, `python3 scripts/recipes.py validate` verifies the
committed detached signature offline against full signer fingerprint
`F40ADB902B24264AA42E50BF92EDB04BFF325CF3`. The upstream signature uses legacy
DSA/SHA-1; [`TRUST.md`](../../../TRUST.md) explains what that evidence does and
does not establish.

The build rejects an ELF interpreter, dynamic dependencies, a wrong machine,
or an incomplete link inventory. Python, Guile, debuginfod, Babeltrace, libipt,
and source-highlight are intentionally disabled to keep the artifact
self-contained.

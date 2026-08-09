# Static GNU readelf 2.47 for AArch64

From the repository root, run:

```sh
./build.sh readelf aarch64
```

The command requires Bash, Docker with Buildx, `file`, `gpgv`, `readelf`, and
`sha256sum`. It uses only the signed source inputs in this directory and the
immutable AArch64 builder lock, then replaces `artifacts/aarch64/readelf` only
after validation.

The result is a stripped static PIE using Binutils' native AArch64 BFD target
profile with static zlib/zstd compressed-section support. NLS, runtime object
plugins, debuginfod, Jansson, and CTF are disabled. It is intended primarily
for objects used on its host architecture, not as a universal cross-toolchain.

The target smoke test checks the exact `2.47.20260726` banner plus ELF file and
program headers, sections, symbols, and DWARF data in a controlled AArch64
executable.

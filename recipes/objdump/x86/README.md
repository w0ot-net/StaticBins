# Static GNU objdump 2.47 for x86

From the repository root, run:

```sh
./build.sh objdump x86
```

The command requires Bash, Docker with Buildx, `file`, `gpgv`, `readelf`, and
`sha256sum`. It uses only the signed source inputs in this directory and the
immutable x86 builder lock, then replaces `artifacts/x86/objdump` only
after validation.

The result is a stripped static PIE using Binutils' native x86 BFD target
profile with static zlib/zstd compressed-section support. NLS, runtime object
plugins, debuginfod, Jansson, and CTF are disabled. It is intended primarily
for objects used on its host architecture, not as a universal cross-toolchain.

The target smoke test checks exact version 2.47 plus object headers, sections,
symbols, and real disassembly of a controlled i686-compatible relocatable
object.

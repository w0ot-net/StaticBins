# Static GNU nm 2.47 for x86-64

From the repository root, run:

```sh
./build.sh nm x86_64
```

The command requires Bash, Docker with Buildx, `file`, `gpgv`, `readelf`, and
`sha256sum`. It uses only the signed source inputs in this directory and the
immutable x86-64 builder lock, then replaces `artifacts/x86_64/nm` only
after validation.

The result is a stripped static PIE using Binutils' native x86-64 BFD target
profile with static zlib/zstd compressed-section support. NLS, runtime object
plugins, debuginfod, Jansson, and CTF are disabled; external LTO plugin objects
are unsupported. It is intended primarily for objects used on its host
architecture, not as a universal cross-toolchain.

The target smoke test checks the exact `2.47.20260726` banner, symbol classes,
defined/undefined filters, name/numeric sorting, and archive-member labels for
controlled x86-64 inputs.

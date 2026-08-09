# static_bins

Ready-to-run static Linux utilities with committed, documented, repeatable
build recipes.

BusyBox, GDB, GDBserver, lsof, ltrace, netcat, netstat, objdump, readelf,
rsync, socat, strace, and tcpdump are available for AArch64, ARMv7, x86, and
x86-64.

## Get a binary

Browse [`artifacts/`](artifacts/) for the distributed executables. Each binary
uses the conventional path:

```text
artifacts/<architecture>/<tool>
```

[`recipes/catalog.tsv`](recipes/catalog.tsv) records the current enabled
`(tool, architecture)` pairs. A checkout can display the same buildable set
with:

```sh
./build.sh list
```

## Verify

From the repository root, check every distributed executable against the
[`artifacts/SHA256SUMS`](artifacts/SHA256SUMS) manifest:

```sh
sha256sum -c artifacts/SHA256SUMS
```

[`TRUST.md`](TRUST.md) records source authentication, recipe build validation,
independent evidence, and the limits of each assurance claim.

## Rebuild

Start from a fresh checkout, inspect the enabled pairs, and select one
explicitly:

```sh
git clone https://github.com/w0ot-net/static_bins.git
cd static_bins
./build.sh list
./build.sh <tool> <architecture>
```

The common prerequisites are Bash, a usable Docker daemon with the Buildx
plugin, and the host commands `file`, `readelf`, and `sha256sum`. Normal builds
use the committed source inputs and the public builder image locked for the
selected architecture. A cold build needs access to that image, and a
non-native build may use QEMU/binfmt registration.

The command creates or replaces `artifacts/<architecture>/<tool>`. The selected
`recipes/<tool>/<architecture>/README.md` owns its pinned version, feature
tradeoffs, additional prerequisites, and validation behavior.

Contributor procedures, maintainer operations, and system architecture are
routed through the [`doc/README.md`](doc/README.md) documentation map.

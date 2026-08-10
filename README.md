# static_bins

Ready-to-run static Linux utilities with committed, documented, repeatable
build recipes.

[Jump to the supported binary catalog](#supported-binaries) for direct artifact
links.

The enabled catalog spans recovery, debugging, networking, file transfer, and
data-inspection tools for AArch64, ARMv7, x86, and x86-64. The machine-readable
[`recipes/catalog.tsv`](recipes/catalog.tsv) remains the inventory authority.

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

## Supported binaries

This table mirrors the enabled entries in
[`recipes/catalog.tsv`](recipes/catalog.tsv). Each available entry links
directly to its committed executable; `-` means that pair is not distributed.

| Binary | AArch64 | ARMv7 | x86 | x86-64 |
| --- | --- | --- | --- | --- |
| [bpftrace](recipes/bpftrace/) | [binary](artifacts/aarch64/bpftrace) | - | - | [binary](artifacts/x86_64/bpftrace) |
| [busybox](recipes/busybox/) | [binary](artifacts/aarch64/busybox) | [binary](artifacts/armv7/busybox) | [binary](artifacts/x86/busybox) | [binary](artifacts/x86_64/busybox) |
| [curl](recipes/curl/) | [binary](artifacts/aarch64/curl) | [binary](artifacts/armv7/curl) | [binary](artifacts/x86/curl) | [binary](artifacts/x86_64/curl) |
| [dropbearmulti](recipes/dropbearmulti/) | [binary](artifacts/aarch64/dropbearmulti) | [binary](artifacts/armv7/dropbearmulti) | [binary](artifacts/x86/dropbearmulti) | [binary](artifacts/x86_64/dropbearmulti) |
| [gdb](recipes/gdb/) | [binary](artifacts/aarch64/gdb) | [binary](artifacts/armv7/gdb) | [binary](artifacts/x86/gdb) | [binary](artifacts/x86_64/gdb) |
| [gdbserver](recipes/gdbserver/) | [binary](artifacts/aarch64/gdbserver) | [binary](artifacts/armv7/gdbserver) | [binary](artifacts/x86/gdbserver) | [binary](artifacts/x86_64/gdbserver) |
| [lsof](recipes/lsof/) | [binary](artifacts/aarch64/lsof) | [binary](artifacts/armv7/lsof) | [binary](artifacts/x86/lsof) | [binary](artifacts/x86_64/lsof) |
| [ltrace](recipes/ltrace/) | [binary](artifacts/aarch64/ltrace) | [binary](artifacts/armv7/ltrace) | [binary](artifacts/x86/ltrace) | [binary](artifacts/x86_64/ltrace) |
| [nc](recipes/nc/) | [binary](artifacts/aarch64/nc) | [binary](artifacts/armv7/nc) | [binary](artifacts/x86/nc) | [binary](artifacts/x86_64/nc) |
| [netstat](recipes/netstat/) | [binary](artifacts/aarch64/netstat) | [binary](artifacts/armv7/netstat) | [binary](artifacts/x86/netstat) | [binary](artifacts/x86_64/netstat) |
| [nm](recipes/nm/) | [binary](artifacts/aarch64/nm) | [binary](artifacts/armv7/nm) | [binary](artifacts/x86/nm) | [binary](artifacts/x86_64/nm) |
| [objdump](recipes/objdump/) | [binary](artifacts/aarch64/objdump) | [binary](artifacts/armv7/objdump) | [binary](artifacts/x86/objdump) | [binary](artifacts/x86_64/objdump) |
| [readelf](recipes/readelf/) | [binary](artifacts/aarch64/readelf) | [binary](artifacts/armv7/readelf) | [binary](artifacts/x86/readelf) | [binary](artifacts/x86_64/readelf) |
| [rsync](recipes/rsync/) | [binary](artifacts/aarch64/rsync) | [binary](artifacts/armv7/rsync) | [binary](artifacts/x86/rsync) | [binary](artifacts/x86_64/rsync) |
| [socat](recipes/socat/) | [binary](artifacts/aarch64/socat) | [binary](artifacts/armv7/socat) | [binary](artifacts/x86/socat) | [binary](artifacts/x86_64/socat) |
| [sqlite3](recipes/sqlite3/) | [binary](artifacts/aarch64/sqlite3) | [binary](artifacts/armv7/sqlite3) | [binary](artifacts/x86/sqlite3) | [binary](artifacts/x86_64/sqlite3) |
| [strace](recipes/strace/) | [binary](artifacts/aarch64/strace) | [binary](artifacts/armv7/strace) | [binary](artifacts/x86/strace) | [binary](artifacts/x86_64/strace) |
| [tcpdump](recipes/tcpdump/) | [binary](artifacts/aarch64/tcpdump) | [binary](artifacts/armv7/tcpdump) | [binary](artifacts/x86/tcpdump) | [binary](artifacts/x86_64/tcpdump) |

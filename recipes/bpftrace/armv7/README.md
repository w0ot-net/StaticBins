# Static bpftrace 0.26.1 for ARMv7

From the repository root, run:

```sh
./build.sh bpftrace armv7
```

The command requires Bash, Docker, and Docker Buildx. It consumes the immutable
ARMv7 builder in `builders/armv7/environment.lock` and replaces
`artifacts/armv7/bpftrace` only after validation and a privileged target
smoke test.

The recipe uses the tracked official bpftrace 0.26.1 archive. Its checksum is
locked, but upstream signing evidence is not adopted for this source snapshot,
so source authentication is explicitly `checksum-only`.

The reviewed Alpine static-link patch corrects the release archive's fallback
patch version, adapts LLVM's static zstd target, enforces the final static link,
supplies BCC's optional debuginfod entry points without adding its network
dependency stack, and gives a `std::max` operand the explicit 32-bit `size_t`
type required by ARMv7.

This approved architecture-limited rollout includes ARMv7, AArch64, and x86-64
only. Alpine excludes its bpftrace package on x86.

The result is a stripped, fully static classic `ET_EXEC` executable with BCC,
libbpf, Clang 20, and LLVM 20 linked in. It uses the system libbpf, omits the
manual and skboutput helper, and deliberately disables remote debuginfod
downloads while retaining local symbol resolution. The static payload is UPX
packed to keep the committed artifact below the repository's 100 MB guard; this
trades some startup CPU and memory for distribution size and can be reversed
with `upx -d`.

The ARMv7 recipe uses a persistent BuildKit compile cache so a late validation
retry can reuse the already compiled objects. It uses UPX level 6 because
maximum LZMA compression is disproportionately slow under QEMU; the selected
level remains below the hosting limit and keeps an emulated rebuild practical.

The recipe explicitly selects non-PIE output because UPX 5.2.0 does not retain
the `DF_1_PIE` dynamic flag required to validate a packed static PIE. Both the
unpacked payload and packed artifact are independently checked for the exact
ARMv7 ELF32, little-endian EABI5 hard-float contract, a nonzero entry point, an
executable load segment, no interpreter or `DT_NEEDED` entries, and stripping.
The packed artifact accepts the equivalent System V and GNU/Linux ELF OS/ABI
labels because UPX marks its ARM decompressor stub as GNU/Linux.
Validation also reconciles the complete final link against the reviewed
provenance inventory, tests UPX integrity, verifies the exact version, and runs
a `BEGIN` program through the parser, LLVM IR verifier, and BPF code generator
under ARMv7 emulation. QEMU linux-user returns `ENOSYS` for the ARMv7 `bpf()`
syscall on the validation host, so the emulated smoke test cannot load the
generated program into the kernel. The x86-64 recipe separately compiles,
loads, and executes its `BEGIN` program against the same host kernel.

# Static bpftrace 0.26.1 for AArch64

From the repository root, run:

```sh
./build.sh bpftrace aarch64
```

The command requires Bash, Docker, and Docker Buildx. It consumes the immutable
AArch64 builder in `builders/aarch64/environment.lock` and replaces
`artifacts/aarch64/bpftrace` only after validation and a privileged target
smoke test.

The recipe uses the tracked official bpftrace 0.26.1 archive. Its checksum is
locked, but upstream signing evidence is not adopted for this source snapshot,
so source authentication is explicitly `checksum-only`.

The reviewed Alpine static-link patch corrects the release archive's fallback
patch version, adapts LLVM's static zstd target, enforces the final static link,
and supplies BCC's optional debuginfod entry points without adding its network
dependency stack.

This approved architecture-limited rollout includes AArch64, ARMv7, and x86-64
only. Alpine excludes its bpftrace package on x86.

The result is a stripped, fully static classic `ET_EXEC` executable with BCC,
libbpf, Clang 20, and LLVM 20 linked in. It uses the system libbpf, omits the
manual and skboutput helper, and deliberately disables remote debuginfod
downloads while retaining local symbol resolution. The static payload is UPX
packed to keep the committed artifact below the repository's 100 MB guard; this
trades some startup CPU and memory for distribution size and can be reversed
with `upx -d`.

The AArch64 recipe uses UPX level 6 because maximum LZMA compression is
disproportionately slow under QEMU; the selected level remains below the
hosting limit and keeps an emulated rebuild practical.

The recipe explicitly selects non-PIE output because UPX 5.2.0 does not retain
the `DF_1_PIE` dynamic flag required to validate a packed static PIE. Both the
unpacked payload and packed artifact are independently checked for the exact
AArch64 ELF contract, a nonzero entry point, an executable load segment, no
interpreter or `DT_NEEDED` entries, and stripping. Validation also reconciles
the complete final link against the reviewed provenance inventory, tests UPX
integrity, verifies the exact version, and runs a `BEGIN` program through the
parser, LLVM IR verifier, and BPF code generator under AArch64 emulation. QEMU
linux-user returns `ENOSYS` for the AArch64 `bpf()` syscall on the validation
host, so the emulated smoke test cannot load the generated program into the
kernel. The x86-64 recipe separately compiles, loads, and executes its `BEGIN`
program against the same host kernel.

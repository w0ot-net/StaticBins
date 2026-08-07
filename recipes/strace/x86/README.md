# Static strace 6.16 for x86

From the repository root, run:

```sh
./build.sh strace x86
```

The command requires Bash, Docker, Docker Buildx, `curl`, `cpio`, `gzip`, and
`qemu-system-i386`. It consumes the immutable x86 builder in
`builders/x86/environment.lock` and replaces `artifacts/x86/strace`
only after validation. When necessary, the script registers pinned x86 QEMU
`binfmt_misc` support if it is not already active.

The recipe uses the tracked official strace 6.16 archive. Its checksum is
locked, but upstream signer-key evidence has not been adopted, so source
authentication is explicitly `checksum-only`.

This self-contained x86 native-personality build uses the release's bundled
Linux UAPI headers. It disables all compatibility personalities, stack
unwinding, symbol demangling through libiberty, and SELinux contexts.
Validation requires a stripped static ELF32 little-endian Intel 80386 `ET_EXEC`
for the repository's i686-compatible CMOV/SSE2 baseline, the exact native
`Optional features enabled: (none)` output,
complete final-link evidence, and a direct-child ptrace test that observes
known `openat`, `write`, and `exit_group` syscalls without extra container
capabilities.

The ptrace test boots a generated diskless QEMU PC initramfs on the fixed
`qemu32` CPU because QEMU user mode does not provide the required x86 ptrace
behavior. The Alpine 3.22.5 x86 kernel URL and checksum are pinned in
`vm.lock`; the verified 8 MB file is cached
outside the repository, while the VM definition and PID 1 test harness are
committed with this recipe.

Source, linked archive, and license evidence are documented in `source.lock`
and `licenses/`.

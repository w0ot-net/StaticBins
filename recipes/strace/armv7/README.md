# Static strace 6.16 for ARMv7

From the repository root, run:

```sh
./build.sh strace armv7
```

The command requires Bash, Docker, Docker Buildx, `curl`, `cpio`, `gzip`, and
`qemu-system-arm`. It consumes the immutable ARMv7 builder in
`builders/armv7/environment.lock` and replaces `artifacts/armv7/strace`
only after validation. On a non-ARMv7 host, the script registers pinned QEMU
`binfmt_misc` support if it is not already active.

The recipe uses the tracked official strace 6.16 archive. Its checksum is
locked, but upstream signer-key evidence has not been adopted, so source
authentication is explicitly `checksum-only`.

This self-contained ARM native-personality build uses the release's bundled
Linux UAPI headers. It disables all compatibility personalities, stack
unwinding, symbol demangling through libiberty, and SELinux contexts.
Validation requires a stripped static ELF32 little-endian ARM hard-float
`ET_EXEC`, the exact native `Optional features enabled: (none)` output,
complete final-link evidence, and a direct-child ptrace test that observes
known `openat`, `write`, and `exit_group` syscalls without extra container
capabilities.

The ptrace test boots a generated diskless QEMU `virt,highmem=off` initramfs
on a Cortex-A15 CPU because QEMU user mode does not provide the required ARMv7
ptrace behavior. The Alpine 3.22.5 kernel URL and checksum are pinned in
`vm.lock`; the verified 8 MB file is cached
outside the repository, while the VM definition and PID 1 test harness are
committed with this recipe.

Source, linked archive, and license evidence are documented in `source.lock`
and `licenses/`.

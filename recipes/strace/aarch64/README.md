# Static strace 6.16 for AArch64

From the repository root, run:

```sh
./build.sh strace aarch64
```

The command requires Bash, Docker, Docker Buildx, `curl`, `cpio`, `gzip`, and
`qemu-system-aarch64`. It consumes the immutable AArch64 builder in
`builders/aarch64/environment.lock` and replaces `artifacts/aarch64/strace`
only after validation. On a non-AArch64 host, the script registers pinned QEMU
`binfmt_misc` support if it is not already active.

The recipe uses the tracked official strace 6.16 archive. Its checksum is
locked, but upstream signer-key evidence has not been adopted, so source
authentication is explicitly `checksum-only`.

This self-contained native-personality build uses the release's bundled Linux
UAPI headers. It disables the AArch32 compatibility personality, stack
unwinding, symbol demangling through libiberty, and SELinux contexts.
Validation requires a stripped static AArch64 `ET_EXEC`, exact feature output,
complete final-link evidence, and a direct-child ptrace test that observes
known `openat`, `write`, and `exit_group` syscalls without extra container
capabilities.

The ptrace test boots a generated diskless QEMU `virt` initramfs because QEMU
user mode does not implement AArch64 `PTRACE_TRACEME`. The Alpine 3.22.5 kernel
URL and checksum are pinned in `vm.lock`; the verified 9 MB file is cached
outside the repository, while the VM definition and PID 1 test harness are
committed with this recipe.

Source, linked archive, and license evidence are documented in `source.lock`
and `licenses/`.

# Static strace 6.16 for x86-64

From the repository root, run:

```sh
./build.sh strace x86_64
```

The command requires Bash, Docker, and Docker Buildx. It consumes the immutable
x86-64 builder in `builders/x86_64/environment.lock` and replaces
`artifacts/x86_64/strace` only after validation.

The recipe uses the tracked official strace 6.16 archive. Its checksum is
locked, but upstream signer-key evidence has not been adopted, so source
authentication is explicitly `checksum-only`.

This self-contained native-personality build uses the release's bundled Linux
UAPI headers. It disables m32/mx32 personalities, stack unwinding, symbol
demangling through libiberty, and SELinux contexts. Validation requires a
stripped static x86-64 `ET_EXEC`, exact feature output, complete final-link
evidence, and a direct-child ptrace test that observes known `openat`, `write`,
and `exit_group` syscalls without extra container capabilities.

Source, linked archive, and license evidence are documented in `source.lock`
and `licenses/`.

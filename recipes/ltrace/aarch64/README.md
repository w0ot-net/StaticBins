# Static ltrace 0.8.1 for AArch64

From the repository root, run:

```sh
./build.sh ltrace aarch64
```

The command requires Bash, Docker, and Docker Buildx. It consumes the immutable
AArch64 builder in `builders/aarch64/environment.lock` and replaces
`artifacts/aarch64/ltrace` only after validation.

The recipe uses the tracked official ltrace 0.8.1 archive. Its checksum is
locked, but upstream signing evidence is not available, so source
authentication is explicitly `checksum-only`. A small reviewed patch prevents
musl's named main-executable link-map entry from being loaded twice. A second
one-line portability patch supplies the AArch64 backend's missing `pid_t`
declaration under musl.

The result is a stripped static PIE with C++ demangling and libelf support. It
omits libdw/libunwind call stacks. The standalone executable traces call names
and return values without runtime data; rich argument decoding additionally
needs ltrace prototype configuration files supplied with upstream ltrace and
selectable with `-F`.

Validation requires the static-PIE invariants, complete final-link evidence,
the exact version, and a direct-child trace of `puts` in a dynamically linked
musl executable inside a pinned AArch64 full-system QEMU smoke VM.

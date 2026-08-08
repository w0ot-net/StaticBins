# Static ltrace 0.8.1 for x86-64

From the repository root, run:

```sh
./build.sh ltrace x86_64
```

The command requires Bash, Docker, and Docker Buildx. It consumes the immutable
x86-64 builder in `builders/x86_64/environment.lock` and replaces
`artifacts/x86_64/ltrace` only after validation.

The recipe uses the tracked official ltrace 0.8.1 archive. Its checksum is
locked, but upstream signing evidence is not available, so source
authentication is explicitly `checksum-only`. A small reviewed patch prevents
musl's named main-executable link-map entry from being loaded twice.

The result is a stripped static PIE with C++ demangling and libelf support. It
omits libdw/libunwind call stacks. The standalone executable traces call names
and return values without runtime data; rich argument decoding additionally
needs ltrace prototype configuration files supplied with upstream ltrace and
selectable with `-F`.

Validation requires the static-PIE invariants, complete final-link evidence,
the exact version, and a direct-child trace of `puts` in a dynamically linked
musl executable.

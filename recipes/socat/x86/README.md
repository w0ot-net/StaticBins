# Static socat 1.8.1.3 for x86

From the repository root, run:

```sh
./build.sh socat x86
```

The command requires Bash, Docker, and Docker Buildx. It consumes the immutable
x86 builder in `builders/x86/environment.lock` and replaces
`artifacts/x86/socat` only after validation. The executable targets the
repository's i686-compatible CMOV/SSE2 CPU baseline.

The recipe uses a tracked, checksum-locked Git archive for official tag
`tag-1.8.1.3` at commit `12c08bf66d709fba17035ce95d85bd218428d9ba`.
The unsigned lightweight tag makes source authentication explicitly
`checksum-only`.

The static build retains file, pipe, UNIX, IPv4/IPv6, TCP/UDP/SCTP, proxy,
exec/system, PTY/TUN, VSOCK, and TLS addresses. TLS uses LibreSSL 4.3.1;
readline, libwrap, and FIPS are disabled. Validation requires a stripped static
ELF32 little-endian x86 `ET_EXEC`, complete final-link evidence, the promised
feature macros, and successful TCP, UNIX-socket, and TLS loopback relays.

Source, linked archive, and license evidence are documented in `source.lock`
and `licenses/`.

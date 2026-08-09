# Static GNU Netcat 0.7.1 for ARMv7

From the repository root, run:

```sh
./build.sh nc armv7
```

The command requires Bash, Docker, Docker Buildx, `file`, `gpgv`,
`readelf`, and `sha256sum`. It consumes the immutable ARMv7 builder
in `builders/armv7/environment.lock` and replaces
`artifacts/armv7/nc` only after complete validation.

The recipe uses the tracked GNU Netcat 0.7.1 release archive, detached
signature, and minimal keyring pinned to
`6247640C1C901EE4D800E4E22D583DF1B2D79FC1`. The release signature is valid
but uses legacy DSA with SHA-1 and the signing key is now expired. A
checksum-locked patches correct two out-of-bounds Linux `IP_PKTINFO`
address-copy lengths and GNU Netcat's unsigned-char port-counting defect.

This is GNU Netcat, not OpenBSD nc or Nmap Ncat. It provides numeric IPv4 TCP
and UDP connect/listen operation, scanning, tunnel mode, and the `-e`
execution feature. It does not provide IPv6, Unix-domain sockets, TLS, or proxy
protocols. GNU Netcat listener mode historically returns status 1 after a
successful completed transfer; validation therefore requires byte-exact TCP
and UDP transfer rather than treating that exit status as success.

The build disables NLS, uses the documented armv7 compiler baseline, and
selects the locked toolchain's stripped static PIE `ET_DYN` profile without an
interpreter, shared dependencies, or text relocations. Source, local-patch,
linked-archive, and license evidence lives
inside this recipe.

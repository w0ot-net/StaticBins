# Trust model

`static_bins` separates source origin, build repeatability, and artifact
validation. None of these checks proves that upstream code is safe or free of
vulnerabilities.

Run the repository's existing validator with `gpgv` installed:

```sh
python3 scripts/recipes.py validate
```

The command works offline. It verifies tracked archive checksums first, then
uses only each recipe's tracked detached signature and minimal signing keyring.
It accepts a PGP record only when `gpgv` reports the full fingerprint pinned in
`source.lock`; it does not use a personal keyring, keyserver, or network lookup.

| Source | Authentication | Full signer fingerprint | Official evidence |
| --- | --- | --- | --- |
| [GDB 17.2](recipes/gdb/aarch64/source.lock) | Upstream PGP | `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` | [signature](https://ftp.gnu.org/gnu/gdb/gdb-17.2.tar.xz.sig); [GNU keyring](https://ftp.gnu.org/gnu/gnu-keyring.gpg) |
| [tcpdump 4.99.4](recipes/tcpdump/x86_64/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/tcpdump-4.99.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |
| [libpcap 1.10.4](recipes/tcpdump/x86_64/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/libpcap-1.10.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |

The GDB signature is valid upstream origin evidence but uses legacy DSA with
SHA-1. The tcpdump and libpcap signatures use RSA with SHA-512. These records
are verified exactly as published; the table does not claim equal
cryptographic strength.

Every source record declares one of two modes:

- `pgp` requires a tracked detached signature, tracked minimal keyring, and
  exact 40-character signer fingerprint. Any verification failure is fatal.
- `checksum-only` is accepted when an upstream signature is unavailable or has
  not been adopted. It still requires a tracked archive, locked SHA-256, and
  official HTTPS provenance URL, and the validator prints the limitation.

`checksum-only` is an explicit assurance level, not a fallback after a bad PGP
signature. An authentic release establishes origin; repeatable builds and
static ELF checks provide different evidence about how the distributed binary
was produced.

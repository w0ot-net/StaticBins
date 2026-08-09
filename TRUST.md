# Trust model

`static_bins` separates source origin, build repeatability, and artifact
validation. None of these checks proves that upstream code is safe or free of
vulnerabilities.

For the stable system-level trust boundaries behind these live records, see
the [trust-chain architecture](doc/architecture/trust/TRUST_CHAIN.md) and
[automation and governance](doc/architecture/trust/AUTOMATION_AND_GOVERNANCE.md).

Run the repository's fast offline validation with `gpgv` installed:

```sh
./validate.sh
```

The source validator composed by this command verifies tracked archive
checksums first, then uses only each recipe's tracked detached signature and
minimal signing keyring. It accepts a PGP record only when `gpgv` reports the
full fingerprint pinned in `source.lock`; it does not use a personal keyring,
keyserver, or network lookup.

| Source | Authentication | Full signer fingerprint | Official evidence |
| --- | --- | --- | --- |
| [BusyBox 1.38.0 (AArch64)](recipes/busybox/aarch64/source.lock) | Checksum only | Not available | [official download](https://busybox.net/downloads/) |
| [BusyBox 1.38.0 (ARMv7)](recipes/busybox/armv7/source.lock) | Checksum only | Not available | [official download](https://busybox.net/downloads/) |
| [BusyBox 1.38.0 (x86)](recipes/busybox/x86/source.lock) | Checksum only | Not available | [official download](https://busybox.net/downloads/) |
| [BusyBox 1.38.0 (x86-64)](recipes/busybox/x86_64/source.lock) | Checksum only | Not available | [official download](https://busybox.net/downloads/) |
| [GDB 17.2](recipes/gdb/aarch64/source.lock) | Upstream PGP | `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` | [signature](https://ftp.gnu.org/gnu/gdb/gdb-17.2.tar.xz.sig); [GNU keyring](https://ftp.gnu.org/gnu/gnu-keyring.gpg) |
| [GDB 17.2 (ARMv7)](recipes/gdb/armv7/source.lock) | Upstream PGP | `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` | [signature](https://ftp.gnu.org/gnu/gdb/gdb-17.2.tar.xz.sig); [GNU keyring](https://ftp.gnu.org/gnu/gnu-keyring.gpg) |
| [GDB 17.2 (x86)](recipes/gdb/x86/source.lock) | Upstream PGP | `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` | [signature](https://ftp.gnu.org/gnu/gdb/gdb-17.2.tar.xz.sig); [GNU keyring](https://ftp.gnu.org/gnu/gnu-keyring.gpg) |
| [GDB 17.2 (x86-64)](recipes/gdb/x86_64/source.lock) | Upstream PGP | `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` | [signature](https://ftp.gnu.org/gnu/gdb/gdb-17.2.tar.xz.sig); [GNU keyring](https://ftp.gnu.org/gnu/gnu-keyring.gpg) |
| [GDB 16.3 (GDBserver, AArch64)](recipes/gdbserver/aarch64/source.lock) | Upstream PGP | `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` | [signature](https://ftp.gnu.org/gnu/gdb/gdb-16.3.tar.xz.sig); [GNU keyring](https://ftp.gnu.org/gnu/gnu-keyring.gpg) |
| [GDB 16.3 (GDBserver, ARMv7)](recipes/gdbserver/armv7/source.lock) | Upstream PGP | `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` | [signature](https://ftp.gnu.org/gnu/gdb/gdb-16.3.tar.xz.sig); [GNU keyring](https://ftp.gnu.org/gnu/gnu-keyring.gpg) |
| [GDB 16.3 (GDBserver, x86)](recipes/gdbserver/x86/source.lock) | Upstream PGP | `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` | [signature](https://ftp.gnu.org/gnu/gdb/gdb-16.3.tar.xz.sig); [GNU keyring](https://ftp.gnu.org/gnu/gnu-keyring.gpg) |
| [GDB 16.3 (GDBserver, x86-64)](recipes/gdbserver/x86_64/source.lock) | Upstream PGP | `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` | [signature](https://ftp.gnu.org/gnu/gdb/gdb-16.3.tar.xz.sig); [GNU keyring](https://ftp.gnu.org/gnu/gnu-keyring.gpg) |
| [lsof 4.99.5 (AArch64)](recipes/lsof/aarch64/source.lock) | Checksum only | Not available | [GitHub release](https://github.com/lsof-org/lsof/releases/tag/4.99.5) |
| [lsof 4.99.5 (ARMv7)](recipes/lsof/armv7/source.lock) | Checksum only | Not available | [GitHub release](https://github.com/lsof-org/lsof/releases/tag/4.99.5) |
| [lsof 4.99.5 (x86)](recipes/lsof/x86/source.lock) | Checksum only | Not available | [GitHub release](https://github.com/lsof-org/lsof/releases/tag/4.99.5) |
| [lsof 4.99.5 (x86-64)](recipes/lsof/x86_64/source.lock) | Checksum only | Not available | [GitHub release](https://github.com/lsof-org/lsof/releases/tag/4.99.5) |
| [ltrace 0.8.1 (AArch64)](recipes/ltrace/aarch64/source.lock) | Checksum only | Not available | [official GitLab release](https://gitlab.com/cespedes/ltrace/-/tags/0.8.1) |
| [ltrace 0.8.1 (ARMv7)](recipes/ltrace/armv7/source.lock) | Checksum only | Not available | [official GitLab release](https://gitlab.com/cespedes/ltrace/-/tags/0.8.1) |
| [ltrace 0.8.1 (x86)](recipes/ltrace/x86/source.lock) | Checksum only | Not available | [official GitLab release](https://gitlab.com/cespedes/ltrace/-/tags/0.8.1) |
| [ltrace 0.8.1 (x86-64)](recipes/ltrace/x86_64/source.lock) | Checksum only | Not available | [official GitLab release](https://gitlab.com/cespedes/ltrace/-/tags/0.8.1) |
| [GNU Netcat 0.7.1 (AArch64)](recipes/nc/aarch64/source.lock) | Upstream PGP | `6247640C1C901EE4D800E4E22D583DF1B2D79FC1` | [signature](https://netcat.sourceforge.net/signatures/netcat-0.7.1.tar.gz.asc); [signer key](https://netcat.sourceforge.net/b2d79fc1.asc) |
| [GNU Netcat 0.7.1 (ARMv7)](recipes/nc/armv7/source.lock) | Upstream PGP | `6247640C1C901EE4D800E4E22D583DF1B2D79FC1` | [signature](https://netcat.sourceforge.net/signatures/netcat-0.7.1.tar.gz.asc); [signer key](https://netcat.sourceforge.net/b2d79fc1.asc) |
| [GNU Netcat 0.7.1 (x86)](recipes/nc/x86/source.lock) | Upstream PGP | `6247640C1C901EE4D800E4E22D583DF1B2D79FC1` | [signature](https://netcat.sourceforge.net/signatures/netcat-0.7.1.tar.gz.asc); [signer key](https://netcat.sourceforge.net/b2d79fc1.asc) |
| [GNU Netcat 0.7.1 (x86-64)](recipes/nc/x86_64/source.lock) | Upstream PGP | `6247640C1C901EE4E800E4E22D583DF1B2D79FC1` | [signature](https://netcat.sourceforge.net/signatures/netcat-0.7.1.tar.gz.asc); [signer key](https://netcat.sourceforge.net/b2d79fc1.asc) |
| [net-tools 2.10 (netstat, AArch64)](recipes/netstat/aarch64/source.lock) | Checksum only | Not available | [official release](https://sourceforge.net/projects/net-tools/files/net-tools-2.10.tar.xz/) |
| [net-tools 2.10 (netstat, ARMv7)](recipes/netstat/armv7/source.lock) | Checksum only | Not available | [official release](https://sourceforge.net/projects/net-tools/files/net-tools-2.10.tar.xz/) |
| [net-tools 2.10 (netstat, x86)](recipes/netstat/x86/source.lock) | Checksum only | Not available | [official release](https://sourceforge.net/projects/net-tools/files/net-tools-2.10.tar.xz/) |
| [net-tools 2.10 (netstat, x86-64)](recipes/netstat/x86_64/source.lock) | Checksum only | Not available | [official release](https://sourceforge.net/projects/net-tools/files/net-tools-2.10.tar.xz/) |
| [socat 1.8.1.3 (AArch64)](recipes/socat/aarch64/source.lock) | Checksum only | Not available | [official Git repository](https://repo.or.cz/socat.git) |
| [socat 1.8.1.3 (ARMv7)](recipes/socat/armv7/source.lock) | Checksum only | Not available | [official Git repository](https://repo.or.cz/socat.git) |
| [socat 1.8.1.3 (x86)](recipes/socat/x86/source.lock) | Checksum only | Not available | [official Git repository](https://repo.or.cz/socat.git) |
| [socat 1.8.1.3 (x86-64)](recipes/socat/x86_64/source.lock) | Checksum only | Not available | [official Git repository](https://repo.or.cz/socat.git) |
| [strace 6.16 (AArch64)](recipes/strace/aarch64/source.lock) | Checksum only | Not adopted | [official release](https://strace.io/files/6.16/) |
| [strace 6.16 (ARMv7)](recipes/strace/armv7/source.lock) | Checksum only | Not adopted | [official release](https://strace.io/files/6.16/) |
| [strace 6.16 (x86)](recipes/strace/x86/source.lock) | Checksum only | Not adopted | [official release](https://strace.io/files/6.16/) |
| [strace 6.16 (x86-64)](recipes/strace/x86_64/source.lock) | Checksum only | Not adopted | [official release](https://strace.io/files/6.16/) |
| [tcpdump 4.99.4 (AArch64)](recipes/tcpdump/aarch64/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/tcpdump-4.99.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |
| [libpcap 1.10.4 (AArch64)](recipes/tcpdump/aarch64/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/libpcap-1.10.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |
| [tcpdump 4.99.4 (ARMv7)](recipes/tcpdump/armv7/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/tcpdump-4.99.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |
| [libpcap 1.10.4 (ARMv7)](recipes/tcpdump/armv7/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/libpcap-1.10.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |
| [tcpdump 4.99.4 (x86)](recipes/tcpdump/x86/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/tcpdump-4.99.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |
| [libpcap 1.10.4 (x86)](recipes/tcpdump/x86/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/libpcap-1.10.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |
| [tcpdump 4.99.4 (x86-64)](recipes/tcpdump/x86_64/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/tcpdump-4.99.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |
| [libpcap 1.10.4 (x86-64)](recipes/tcpdump/x86_64/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/libpcap-1.10.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |

The GDB and GNU Netcat signatures are valid upstream origin evidence but use
legacy DSA with SHA-1. The GNU Netcat signing key is also expired. The tcpdump
and libpcap signatures use RSA with SHA-512. These records are verified exactly
as published; the table does not claim equal cryptographic strength.

BusyBox labels 1.38.0 an unstable release. Although upstream publishes a DSA
signature, these recipes have not adopted a signer key backed by authenticated
official full-fingerprint evidence. They therefore select `checksum-only`
explicitly and do not attempt PGP verification or fall back after a failed
signature check.

The net-tools 2.10 release directory does not provide a detached signature
over the accepted archive with authenticated full-fingerprint key evidence,
so the netstat recipes select `checksum-only`. Their separately
checksum-locked interface-counter patch is retained from an immutable Alpine
aports revision and links to the upstream discussion; it is reviewed
downstream evidence, not authentication of the release archive.

The AArch64 GDBserver, ltrace, and strace functional tests boot the same
checksum-locked Alpine 3.22.5 `vmlinuz-virt`, recorded in their respective
[`GDBserver vm.lock`](recipes/gdbserver/aarch64/vm.lock) and
[`ltrace vm.lock`](recipes/ltrace/aarch64/vm.lock), and
[`strace vm.lock`](recipes/strace/aarch64/vm.lock). The kernel is a downloaded
smoke-test environment input, not a linked input or distributed artifact. Its
checksum verifies accepted bytes but does not authenticate their origin.

The ARMv7 GDBserver, ltrace, and strace functional tests boot the same checksum-locked
Alpine 3.22.5 `vmlinuz-lts`, recorded in their respective
[`GDBserver vm.lock`](recipes/gdbserver/armv7/vm.lock) and
[`ltrace vm.lock`](recipes/ltrace/armv7/vm.lock), and
[`strace vm.lock`](recipes/strace/armv7/vm.lock). Its published configuration
and an evidence boot establish the required QEMU `virt`, PL011 console, and
generated-initramfs support. The same checksum-only kernel limitation applies.

The x86 GDBserver, ltrace, and strace functional tests boot the same checksum-locked
Alpine 3.22.5 x86 `vmlinuz-lts`, recorded in their respective
[`GDBserver vm.lock`](recipes/gdbserver/x86/vm.lock) and
[`ltrace vm.lock`](recipes/ltrace/x86/vm.lock), and
[`strace vm.lock`](recipes/strace/x86/vm.lock). The published configuration and
successful QEMU PC boots establish 32-bit x86, initramfs, devtmpfs, procfs, and
8250 serial-console support; both guests also verify that the fixed `qemu32`
CPU exposes CMOV and SSE2. The kernel remains a smoke-test environment input,
not a linked input or distributed artifact, and its checksum does not
authenticate its origin.

strace publishes a detached release signature, but these recipes have not
adopted a signer key backed by authenticated official full-fingerprint
evidence. They choose `checksum-only` explicitly and do not attempt PGP
verification or fall back after a failed signature check.

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

## Artifact records

From the repository root, check every distributed file against the committed
integrity manifest:

```sh
sha256sum -c artifacts/SHA256SUMS
```

This detects missing or changed bytes relative to the checked-out manifest. The
validator also requires the manifest's artifact paths to equal the conventional
outputs derived from `recipes/catalog.tsv`. Each artifact therefore maps to the
validated `recipes/<tool>/<architecture>/source.lock` records summarized above.
Checksums and source authentication do not identify who built a binary.

Every distributed artifact was built through its committed recipe and passed
that recipe's source, link, ELF, architecture, version, and focused functional
checks. Target execution may be native or use the recipe's supported
Buildx/QEMU path.

Only the following artifacts have independent evidence beyond those required
recipe checks:

| Artifact | Independent evidence |
| --- | --- |
| `artifacts/aarch64/gdb` | One native exact-rebuild mismatch |
| `artifacts/x86_64/tcpdump` | Exact native rebuild and historical GitHub attestation |

Every artifact not listed in this exception table has no independent rebuild
or attestation evidence. That absence does not mean its required recipe checks
were skipped.

The tcpdump evidence records a clean native build that reproduced the committed
SHA-256 exactly and a past repository workflow that attested the same rebuilt
file. Verify that historical attestation with a current GitHub CLI:

```sh
gh attestation verify artifacts/x86_64/tcpdump \
  --repo w0ot-net/static_bins \
  --signer-workflow w0ot-net/static_bins/.github/workflows/verify-artifacts.yml \
  --source-ref refs/heads/main
```

The initial native checks on 2026-08-07 reproduced tcpdump as
`cdd8f895dceb63d428f137ed910cc083dde2bc76d1006e3468b6f8d654c053b1`.
The single required GDB check produced
`8e729a88937e2187a9288ae9914748ae3946285227a76ce37232802df8319f4a`
instead of the committed
`5e96e51367020e6be6e2cb0a7f0014573da838a8f7d1d099fd2e5a4a55c820ab`;
the committed file was restored unchanged and no retry was made.

The signer workflow identity above is literal historical evidence even though
that workflow is no longer part of the repository's acceptance mechanism. An
attestation ties exact bytes to one past workflow execution and commit; it does
not prove that the source is safe, reviewed, malware-free, or free of
vulnerabilities.

## Repository governance

The active [`main-history` ruleset](https://github.com/w0ot-net/static_bins/rules/20544422)
targets only `main` and blocks deletion and non-fast-forward updates. Direct
pushes are allowed; pull requests and successful hosted checks are not required
before a commit reaches `main`. Maintainers run `./validate.sh` before pushing
and run the narrow recipe or builder validation when those paths change.
The read-only `repository-validation` GitHub Actions job also runs
`./validate.sh` on pushes to `main` and pull requests as advisory clean-checkout
feedback; it does not build, publish, or attest artifacts and is not an
acceptance gate.
Builder publication is a separate local maintainer operation that uses Docker's
external GHCR credentials and reports an immutable digest for reviewed
adoption.

These controls protect existing history from destructive updates, but they do
not guarantee review or successful local validation before publication.
Repository write access and the owner who can change settings or push directly
therefore remain explicit trust boundaries, alongside the upstream sources,
local Docker execution and credentials, builders, registry, and ruleset
services described above.

When verifying the historical tcpdump attestation, require repository
`w0ot-net/static_bins`, signer workflow
`w0ot-net/static_bins/.github/workflows/verify-artifacts.yml`, and source ref
`refs/heads/main`. The successful GitHub CLI output identifies the source
commit; users can additionally confirm that commit remains reachable from the
protected `main` history. Neither history protection nor that identity check
establishes that the program is benign.

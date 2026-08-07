# Trust model

`static_bins` separates source origin, build repeatability, and artifact
validation. None of these checks proves that upstream code is safe or free of
vulnerabilities.

For the stable system-level trust boundaries behind these live records, see
the [trust-chain architecture](doc/architecture/trust/TRUST_CHAIN.md) and
[automation and governance](doc/architecture/trust/AUTOMATION_AND_GOVERNANCE.md).

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
| [GDB 16.3 (GDBserver, AArch64)](recipes/gdbserver/aarch64/source.lock) | Upstream PGP | `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` | [signature](https://ftp.gnu.org/gnu/gdb/gdb-16.3.tar.xz.sig); [GNU keyring](https://ftp.gnu.org/gnu/gnu-keyring.gpg) |
| [GDB 16.3 (GDBserver, x86-64)](recipes/gdbserver/x86_64/source.lock) | Upstream PGP | `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` | [signature](https://ftp.gnu.org/gnu/gdb/gdb-16.3.tar.xz.sig); [GNU keyring](https://ftp.gnu.org/gnu/gnu-keyring.gpg) |
| [lsof 4.99.5 (AArch64)](recipes/lsof/aarch64/source.lock) | Checksum only | Not available | [GitHub release](https://github.com/lsof-org/lsof/releases/tag/4.99.5) |
| [lsof 4.99.5 (x86-64)](recipes/lsof/x86_64/source.lock) | Checksum only | Not available | [GitHub release](https://github.com/lsof-org/lsof/releases/tag/4.99.5) |
| [socat 1.8.1.3 (AArch64)](recipes/socat/aarch64/source.lock) | Checksum only | Not available | [official Git repository](https://repo.or.cz/socat.git) |
| [socat 1.8.1.3 (x86-64)](recipes/socat/x86_64/source.lock) | Checksum only | Not available | [official Git repository](https://repo.or.cz/socat.git) |
| [strace 6.16 (AArch64)](recipes/strace/aarch64/source.lock) | Checksum only | Not adopted | [official release](https://strace.io/files/6.16/) |
| [strace 6.16 (x86-64)](recipes/strace/x86_64/source.lock) | Checksum only | Not adopted | [official release](https://strace.io/files/6.16/) |
| [tcpdump 4.99.4](recipes/tcpdump/x86_64/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/tcpdump-4.99.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |
| [libpcap 1.10.4](recipes/tcpdump/x86_64/source.lock) | Upstream PGP | `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D` | [signature](https://www.tcpdump.org/release/libpcap-1.10.4.tar.gz.sig); [Tcpdump Group key](https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc) |

The GDB signature is valid upstream origin evidence but uses legacy DSA with
SHA-1. The tcpdump and libpcap signatures use RSA with SHA-512. These records
are verified exactly as published; the table does not claim equal
cryptographic strength.

The AArch64 GDBserver and strace functional tests boot the same
checksum-locked Alpine 3.22.5 `vmlinuz-virt`, recorded in their respective
[`GDBserver vm.lock`](recipes/gdbserver/aarch64/vm.lock) and
[`strace vm.lock`](recipes/strace/aarch64/vm.lock). The kernel is a downloaded
smoke-test environment input, not a linked input or distributed artifact. Its
checksum verifies accepted bytes but does not authenticate their origin.

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

## Artifact assurance

From the repository root, check every distributed file against the committed
integrity manifest:

```sh
sha256sum -c artifacts/SHA256SUMS
```

This detects missing or changed bytes relative to the checked-out manifest. It
does not identify who built a binary or establish its provenance.

| Artifact | Source authentication | Artifact status |
| --- | --- | --- |
| `artifacts/aarch64/gdb` | Upstream PGP | `Not verified` |
| `artifacts/aarch64/gdbserver` | Upstream PGP | `Not verified` |
| `artifacts/aarch64/lsof` | Checksum only | `Not verified` |
| `artifacts/aarch64/socat` | Checksum only | `Not verified` |
| `artifacts/aarch64/strace` | Checksum only | `Not verified` |
| `artifacts/x86_64/tcpdump` | Upstream PGP for tcpdump and libpcap | `Exact rebuild + GitHub attestation` |
| `artifacts/x86_64/gdbserver` | Upstream PGP | `Not verified` |
| `artifacts/x86_64/lsof` | Checksum only | `Not verified` |
| `artifacts/x86_64/socat` | Checksum only | `Not verified` |
| `artifacts/x86_64/strace` | Checksum only | `Not verified` |

`Exact rebuild + GitHub attestation` means a clean native build passed the
recipe checks, reproduced the committed SHA-256 exactly, and the repository
workflow attested that same rebuilt file. Verify tcpdump with a current GitHub
CLI:

```sh
gh attestation verify artifacts/x86_64/tcpdump \
  --repo w0ot-net/static_bins \
  --signer-workflow w0ot-net/static_bins/.github/workflows/verify-artifacts.yml \
  --source-ref refs/heads/main
```

`Not verified` means no exact rebuild-and-attestation claim is available. The
initial native checks on 2026-08-07 reproduced tcpdump as
`cdd8f895dceb63d428f137ed910cc083dde2bc76d1006e3468b6f8d654c053b1`.
The single required GDB check produced
`8e729a88937e2187a9288ae9914748ae3946285227a76ce37232802df8319f4a`
instead of the committed
`5e96e51367020e6be6e2cb0a7f0014573da838a8f7d1d099fd2e5a4a55c820ab`;
the committed file was restored unchanged and no retry was made.

An attestation ties exact bytes to a repository workflow execution and commit;
it does not prove that the source is safe, reviewed, malware-free, or free of
vulnerabilities.

## Repository governance

The active [`main-history` ruleset](https://github.com/w0ot-net/static_bins/rules/20544422)
targets only `main` and blocks deletion and non-fast-forward updates. Direct
pushes are allowed; pull requests and successful CI checks are not required
before a commit reaches `main`. The `recipe-validation` and
`artifact-assurance` jobs remain useful post-push signals when their workflow
triggers select a change. Repository Actions policy requires every
[`uses:` reference](.github/workflows) to name a full commit SHA.

These controls protect existing history from destructive updates and make
workflow dependencies explicit, but they do not guarantee review or a
successful check before publication. Repository write access and the owner who
can change settings or push directly therefore remain explicit trust
boundaries, alongside GitHub's identity, Actions, attestation, and ruleset
services and the upstream sources and builders described above.

When verifying an attestation, require repository `w0ot-net/static_bins`, signer
workflow [`.github/workflows/verify-artifacts.yml`](.github/workflows/verify-artifacts.yml),
and source ref `refs/heads/main`. The successful GitHub CLI output identifies
the source commit; users can additionally confirm that commit remains reachable
from the protected `main` history. Neither history protection nor that identity
check establishes that the program is benign.

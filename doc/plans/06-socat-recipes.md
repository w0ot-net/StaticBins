# Plan: Add socat Recipes for Both Architectures

*Distilled: 2026-08-07*

## Summary

Replace the legacy x86-64 socat and add AArch64 socat with version 1.8.1.3
recipes that preserve the existing broad relay feature profile, including the
OpenSSL-compatible TLS addresses and SCTP but excluding readline. Build that
TLS support against static LibreSSL, inventory the complete link, and require
both cleartext relay and TLS loopback tests before artifact replacement.

This plan depends on `01-multi-architecture-recipe-selection.md`,
`02-narrow-tcpdump-assurance-selection.md`, and
`03-expand-reusable-builders.md`.

## Problem

The existing x86-64 socat is a stripped static 1.7.4.4 executable with IPv4,
IPv6, UNIX sockets, TCP/UDP/SCTP, exec/system, TUN/PTY, VSOCK, and the OpenSSL
API feature, but there is no recipe or linked-license evidence. AArch64 has no
socat artifact. Rebuilding 1.7.4.4 against Alpine 3.24.1's LibreSSL fails on
the removed `OPENSSL_INIT_SETTINGS` type, while statically linking Alpine's
Apache-2.0 OpenSSL 3 into GPL-2.0-only socat is not covered by socat's exception
for the older OpenSSL/SSLeay license. The smallest distributable TLS-capable
profile therefore uses the current 1.8.1.3 source, which builds against the
locked BSD/ISC-licensed LibreSSL packages.

## Scope

In scope:

- Upgrade only socat to 1.8.1.3 while preserving the current feature contract:
  stdio/files/pipes, UNIX/abstract sockets, IPv4/IPv6/raw/generic sockets,
  TCP/UDP/SCTP, listen, SOCKS/proxy, exec/system, VSOCK, TUN/PTY, the
  OpenSSL-compatible address family, sycls, filan, and retry; readline,
  libwrap, and FIPS remain disabled.
- Add enabled recipes for AArch64 and x86-64 using the expanded architecture
  builders and no ordinary-build package resolution.
- Retain a deterministic uncompressed tar archive made from official HTTPS Git
  tag `tag-1.8.1.3` at exact commit
  `12c08bf66d709fba17035ce95d85bd218428d9ba`, SHA-256
  `7435e6ee10d41c5254a2dfaef14b24eb25dc47588862a5c957b37ec1b0f205ab`,
  under `checksum-only` authentication because the tag is lightweight and
  unsigned.
- Build static native executables with the OpenSSL-compatible API and SCTP
  explicitly enabled, LibreSSL selected as the TLS implementation, and
  readline explicitly disabled; reconcile every final linked archive.
- Exercise deterministic local data relay and a TLS client/server exchange on
  the target architecture.
- Replace/add artifacts, manifests, full license/exception notices, and concise
  docs while retaining `Not verified` status.

Out of scope:

- Preserving the old 1.7.4.4 bytes, linking Apache-2.0 OpenSSL 3, bypassing TLS
  certificate verification during source acquisition, or treating the
  unsigned Git tag as PGP evidence.
- Enabling readline, libwrap, FIPS mode, or privileged TUN/VSOCK integration
  tests.
- Exact-rebuild qualification, artifact attestation, utility images, or
  generic network-test infrastructure.

## Design

Create `recipes/socat/{aarch64,x86_64}/` using the conventional owner layout.
Clone `https://repo.or.cz/socat.git` into temporary storage, require
`tag-1.8.1.3` to resolve to the exact pinned commit, and create the accepted
archive with `git archive --format=tar --prefix=socat-1.8.1.3/ <commit>`. Name
the tracked tar consistently in each source lock, record the official Git URL
and `SOURCE_AUTHENTICATION=checksum-only`, and record the tag/commit/archive
command in `NOTICE.md`. The checksum remains the normal-build acceptance lock;
ordinary builds use only the tracked tar and do not clone or download source.

Because the Git archive does not contain generated `configure`, run
`autoreconf -fi` with the locked builder before configuring. Use optimization
plus `-static -no-pie`, `--enable-openssl`, `--enable-sctp`, and
`--disable-readline`, and require configure/link evidence that `libssl.a` and
`libcrypto.a` are owned by the pinned LibreSSL packages. Require `socat -V` to
match the complete promised macro set (which retains the upstream
`WITH_OPENSSL` API name) and fail if an intentionally omitted feature appears
or a promised one is absent. Generate a linker map and reconcile socat source,
musl/GCC, LibreSSL, and every other observed archive against exact versions,
Alpine source evidence, and reviewed license text.

The distribution materials must include socat's GPL-2.0 text, the BSD/ISC
LibreSSL notices, and every other final-link license. Retain upstream
`COPYING.OpenSSL` as source-distribution material but state that the final link
uses LibreSSL and does not rely on that exception or include Apache-2.0 OpenSSL.

Run functional tests inside the target builder/runtime boundary. First relay a
unique byte sequence across bounded loopback TCP and UNIX-socket endpoints.
Then generate an ephemeral test key/certificate with LibreSSL's
OpenSSL-compatible command, start an `OPENSSL-LISTEN` endpoint bound only to
loopback, use the candidate as the verification-disabled test client, and
require the same payload to traverse TLS. Use ephemeral ports, explicit
timeouts, process traps, and no host-network or public bind. The host script
separately enforces correct machine, `ET_EXEC`, stripped state, no interpreter,
and no `DT_NEEDED` before installing the candidate.

## Affected Components

- `recipes/socat/aarch64/*` and `recipes/socat/x86_64/*`: add locked source,
  static builds, feature/relay/TLS tests, READMEs, notices, license exception
  material, and linked-archive inventories.
- `recipes/catalog.tsv`: add enabled socat rows for both architectures.
- `artifacts/aarch64/socat` and `artifacts/x86_64/socat`: add/replace only
  fully validated executables.
- `artifacts/SHA256SUMS`: add sorted exact records for both artifacts.
- `README.md`: list socat 1.8.1.3 and link its architecture recipes concisely.
- `TRUST.md`: record checksum-only source transport, replace the legacy row,
  add AArch64, and keep both artifact statuses `Not verified`.

## Implementation Sequence

1. Clone the official Git repository into temporary storage, verify the tag's
   exact commit, generate the deterministic tar with the prescribed prefix,
   verify its locked hash/size, and explicitly add the same accepted bytes to
   each recipe.
2. Build one architecture with the exact feature flags, capture/reconcile the
   link map, and implement aggregate feature diagnostics plus bounded relay/TLS
   smoke tests.
3. Port architecture constants to the second recipe and run each expensive
   build once, preserving cache and diagnostic outputs for late failures.
4. Add both catalog rows, atomically add/replace artifacts only after all tests,
   update the sorted checksum manifest, and revise bounded user/trust docs.

## Validation

- Run `python3 scripts/recipes.py validate` and require both socat source locks
  to report checksum-only; run unit tests, shell syntax checks,
  `./build.sh list`, and `git diff --check`.
- Run `./build.sh socat x86_64` and `./build.sh socat aarch64` once each. Check
  exact version 1.8.1.3 and the full promised/omitted feature set, correct
  machine/`ET_EXEC`, stripped state, no interpreter/`DT_NEEDED`, complete link
  inventory, and LibreSSL ownership of the TLS archives.
- Require successful target-architecture TCP/UNIX relay and ephemeral TLS
  loopback tests; version/macro output alone is insufficient.
- Run `sha256sum -c artifacts/SHA256SUMS`, inspect final modes/sizes, and verify
  only the intended old x86-64 socat was replaced.
- Confirm no tcpdump exact build, socat attestation claim, public network
  listener, source TLS bypass, or utility container was introduced.

## Success Criteria

- Both explicit root commands rebuild socat 1.8.1.3 from tracked accepted
  source and immutable reusable builders with no normal-build downloads.
- Both artifacts are stripped static native executables with the documented
  broad feature profile and successful cleartext/TLS relay behavior.
- The unsigned-tag limitation, exact official Git commit, LibreSSL link, all
  inputs/licenses, checksums, and `Not verified` statuses are accurately
  recorded.

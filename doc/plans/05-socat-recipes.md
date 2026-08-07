# Plan: Add socat Recipes for Both Architectures

## Summary

Replace the legacy x86-64 socat and add AArch64 socat with version 1.7.4.4
recipes that preserve the existing broad relay feature profile, including
OpenSSL and SCTP but excluding readline. Use one tracked checksum-locked source
archive per architecture, inventory the large static OpenSSL link, and require
both cleartext relay and TLS loopback tests before artifact replacement.

This plan depends on `01-multi-architecture-recipe-selection.md` and
`02-expand-reusable-builders.md`.

## Problem

The existing x86-64 socat is a stripped static 1.7.4.4 executable with IPv4,
IPv6, UNIX sockets, TCP/UDP/SCTP, exec/system, TUN/PTY, VSOCK, and OpenSSL, but
there is no recipe or linked-license evidence. AArch64 has no socat artifact.
Building a smaller default executable or merely checking `socat -V` would
silently lose important behavior or fail to exercise its dominant static TLS
dependency.

## Scope

In scope:

- Preserve socat 1.7.4.4 and the current feature contract: stdio/files/pipes,
  UNIX/abstract sockets, IPv4/IPv6/raw/generic sockets, TCP/UDP/SCTP, listen,
  SOCKS/proxy, exec/system, VSOCK, TUN/PTY, OpenSSL, sycls, filan, and retry;
  readline, libwrap, and FIPS remain disabled.
- Add enabled recipes for AArch64 and x86-64 using the expanded architecture
  builders and no ordinary-build package resolution.
- Retain `socat_1.7.4.4.orig.tar.gz` from Debian's HTTPS original-source mirror,
  SHA-256
  `0f8f4b9d5c60b8c53d17b60d79ababc4a0f51b3bb6d2bd3ae8a6a4b9d68f195e`,
  under `checksum-only` authentication, and document that transport choice
  because the upstream project's archive host does not provide a currently
  verifiable TLS chain or adopted detached signature.
- Build static native executables with OpenSSL and SCTP explicitly enabled and
  readline explicitly disabled, then reconcile every final linked archive.
- Exercise deterministic local data relay and a TLS client/server exchange on
  the target architecture.
- Replace/add artifacts, manifests, full license/exception notices, and concise
  docs while retaining `Not verified` status.

Out of scope:

- Upgrading to socat 1.8.x, synthesizing a source tarball from Git, bypassing
  certificate verification, or treating a third-party mirror as PGP evidence.
- Enabling readline, libwrap, FIPS mode, or privileged TUN/VSOCK integration
  tests.
- Exact-rebuild qualification, artifact attestation, utility images, or
  generic network-test infrastructure.

## Design

Create `recipes/socat/{aarch64,x86_64}/` using the conventional owner layout.
Name the tracked bytes consistently with the source lock, record the valid
Debian HTTPS original-source URL and `SOURCE_AUTHENTICATION=checksum-only`, and
also explain the upstream project/repository provenance in `NOTICE.md`. Normal
builds use only the tracked bytes and never invoke the problematic upstream
TLS endpoint.

Configure with optimization plus `-static -no-pie`, `--enable-openssl`,
`--enable-sctp`, and `--disable-readline`, using only source-level flags.
Require `socat -V` to match the complete promised macro set and fail if an
intentionally omitted feature appears or a promised one is absent. Generate a
linker map and reconcile socat source, musl/GCC, `libssl.a`, `libcrypto.a`, and
any other observed archive against exact versions, Alpine source evidence, and
reviewed license text.

The distribution materials must include socat's GPL-2.0 text, its explicit
OpenSSL linking exception and `COPYING.OpenSSL`, OpenSSL's Apache-2.0 text, and
all other final-link licenses. The notice states the facts without making a
general legal-compatibility claim.

Run functional tests inside the target builder/runtime boundary. First relay a
unique byte sequence across bounded loopback TCP and UNIX-socket endpoints.
Then generate an ephemeral test key/certificate with the locked builder's
OpenSSL command, start an `OPENSSL-LISTEN` endpoint bound only to loopback, use
the candidate as the verifying-disabled test client, and require the same
payload to traverse TLS. Use ephemeral ports, explicit timeouts, process traps,
and no host-network or public bind. The host script separately enforces correct
machine, `ET_EXEC`, stripped state, no interpreter, and no `DT_NEEDED` before
installing the candidate.

## Affected Components

- `recipes/socat/aarch64/*` and `recipes/socat/x86_64/*`: add locked source,
  static builds, feature/relay/TLS tests, READMEs, notices, license exception
  material, and linked-archive inventories.
- `recipes/catalog.tsv`: add enabled socat rows for both architectures.
- `artifacts/aarch64/socat` and `artifacts/x86_64/socat`: add/replace only
  fully validated executables.
- `artifacts/SHA256SUMS`: add sorted exact records for both artifacts.
- `README.md`: list socat 1.7.4.4 and link its architecture recipes concisely.
- `TRUST.md`: record checksum-only source transport, replace the legacy row,
  add AArch64, and keep both artifact statuses `Not verified`.

## Implementation Sequence

1. Fetch the Debian original-source archive into temporary storage, verify the
   locked hash/size, compare its source identity and license materials, and
   explicitly add the accepted bytes to each recipe.
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
  exact version and the full promised/omitted feature set, correct
  machine/`ET_EXEC`, stripped state, no interpreter/`DT_NEEDED`, and complete
  link inventory.
- Require successful target-architecture TCP/UNIX relay and ephemeral TLS
  loopback tests; version/macro output alone is insufficient.
- Run `sha256sum -c artifacts/SHA256SUMS`, inspect final modes/sizes, and verify
  only the intended old x86-64 socat was replaced.
- Confirm no tcpdump exact build, socat attestation claim, public network
  listener, source TLS bypass, or utility container was introduced.

## Success Criteria

- Both explicit root commands rebuild socat 1.7.4.4 from tracked accepted
  source and immutable reusable builders with no normal-build downloads.
- Both artifacts are stripped static native executables with the documented
  broad feature profile and successful cleartext/TLS relay behavior.
- The weaker source transport, OpenSSL exception, all linked inputs/licenses,
  checksums, and `Not verified` statuses are accurately recorded.

# Plan: Add Standalone Telnet Across Ready Architectures

**ABANDONED 2026-08-08**: Every distributed BusyBox artifact already provides
the telnet client through `busybox telnet`. A separate `telnet` artifact would
duplicate source inputs, four recipes, four binaries, and their maintenance
solely for command-name convenience, contrary to the repository's goal of the
smallest practical rebuild process. No replacement plan is needed.

## Summary

Add a directly executable `telnet` client for `aarch64`, `armv7`, `x86`, and
`x86_64`. Build a client-only BusyBox 1.38.0 binary from the same reviewed
release already used by the repository, with a minimal committed configuration
and the existing immutable builders. Do not copy the broad BusyBox artifact or
introduce inetutils, new builder packages, shared recipe machinery, or a telnet
server.

## Problem

The distributed BusyBox binary contains a telnet applet, but users must know to
invoke it as `busybox telnet`; there is no conventional
`artifacts/<architecture>/telnet` executable. Copying that 407-applet binary
under another name would duplicate unrelated functionality, while adding a
different telnet implementation would introduce another source and a larger
dependency surface without improving the requested client workflow.

Telnet also carries terminal input, output, and login information without
transport encryption. A standalone artifact must make that limitation and its
intended trusted-network, lab, or recovery use explicit rather than presenting
it as an SSH replacement.

## Scope

In scope:

- Add `artifacts/<architecture>/telnet` and one complete enabled recipe for
  each of the four ready architectures.
- Build only the BusyBox telnet client applet, including IPv4/IPv6 connection,
  terminal-type, automatic-login, and window-size negotiation support.
- Preserve the repository's tracked-source, immutable-builder, final-link
  inventory, static-ELF, target-runtime, checksum, and trust contracts.
- Prove direct basename dispatch, exact version/help output, and a real bounded
  loopback telnet connection and negotiation on every target architecture.
- Document the plaintext security boundary and remove the root README's stale
  hand-maintained tool enumeration in favor of the catalog it already names as
  authoritative.

Out of scope:

- `telnetd`, inetd integration, a login service, PAM, TLS, SSH, proxies, or any
  server-side configuration.
- Changing the existing BusyBox artifact, its 407-applet profile, or its
  recipe; distributing a copied full BusyBox binary, symlink, or wrapper as
  `telnet`.
- Selecting or updating a different upstream telnet implementation, promising
  compatibility with every historical telnet extension, or adding an
  adversarial protocol test suite.
- Builder changes or publication, runtime utility images, catalog/schema or
  dispatcher changes, generic recipe/validator refactors, exact-rebuild claims,
  or provenance attestations.

## Design

Use the exact official BusyBox 1.38.0 archive already accepted by the BusyBox
recipes: `busybox-1.38.0.tar.bz2`, 2,695,723 bytes, SHA-256
`34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2`,
and `GPL-2.0-only`. Each telnet recipe owns an identical regular mode-`100644`
copy under its `sources/` directory and declares `checksum-only`; do not imply
that reuse of reviewed bytes upgrades the upstream authentication. Keep the
upstream 1.38.0 unstable-release warning in each recipe README.

Commit a complete resolved BusyBox configuration per architecture, produced
from the narrowest configuration rather than editing the broad BusyBox
defconfig. Enable the `busybox` dispatch mechanism, static linking, the
`telnet` applet, IPv6, terminal type, `-a`/`-l USER`, and window-size support;
leave `telnetd` and every unrelated applet disabled. Commit an expected applet
inventory containing only `telnet`, and make `oldconfig` plus the runtime
inventory fail if upstream defaults or the feature surface drift.

Build the minimal BusyBox executable with the architecture's locked GHCR
builder and deterministic timestamp controls, record the final linker map, and
copy the candidate across the scratch output boundary as `/telnet`. BusyBox
dispatches by `argv[0]`, so the regular ELF file directly executes the telnet
client when installed at that name; it has no runtime dependency on
`artifacts/<architecture>/busybox`, a symlink farm, or a shell wrapper. Export
only `/telnet` and leave all intermediate BusyBox names and build outputs in
temporary/container state.

Use the existing BusyBox recipe shape as a bounded implementation reference,
not as a reason to add a shared framework. Retain only license texts applicable
to the actual final link. Reconcile every source-built BusyBox archive and
builder archive observed in the new link map against exact package, version,
license, and immutable source evidence; reject both uninventoried linked
archives and inventory rows absent from the link. The current locked builders
already compile BusyBox and therefore require no package or digest change.

Select the locked toolchains' static PIE `ET_DYN` profile. Before and after
installation require the repository's exact machine, ELF class, endianness,
ABI, nonzero entry point, executable `PT_LOAD`, `DF_1_PIE`, no `PT_INTERP`, no
`DT_NEEDED`, no text relocation, and stripped-output invariants. Preserve the
documented ARMv7 hard-float checks and explicit x86 i686/CMOV/SSE2 baseline.

Run smoke validation inside the target builder with networking disabled outside
the container. First invoke the candidate directly as `telnet --help` and
require the BusyBox 1.38.0 version plus the expected client-only usage and
options. Then use a bounded target-local loopback fixture on an unprivileged
port to send a deterministic banner and a telnet option request, run the
candidate with a numeric host and explicit port, and assert that the banner is
delivered without negotiation bytes and that the expected negotiation response
returns to the fixture. Bound listener and client lifetime, reap the listener,
and report captured diagnostics on failure so a hang cannot stall a build.

Add four sorted catalog rows and conventional artifacts atomically. Update the
artifact manifest and four checksum-only source rows in `TRUST.md`; leave the
artifact-evidence exceptions unchanged unless independent evidence is actually
created. In `README.md`, replace the already incomplete literal tool list with
a concise direction to `recipes/catalog.tsv`/`./build.sh list`, avoiding another
derived inventory that will become stale. No architecture page changes because
the rollout conforms to, rather than changes, the stable system contracts.

## Affected Components

- `recipes/telnet/{aarch64,armv7,x86,x86_64}/`: add Dockerfiles, host/guest
  builds, minimal resolved configurations, one-applet inventories, ELF and
  loopback smoke validation, READMEs, source locks/archives, and exact
  license/final-link evidence.
- `recipes/catalog.tsv`: add four enabled `telnet` rows.
- `artifacts/{aarch64,armv7,x86,x86_64}/telnet`: add the four validated regular
  executable artifacts.
- `artifacts/SHA256SUMS`: add four sorted exact checksum records.
- `TRUST.md`: add the four BusyBox 1.38.0 telnet source-authentication records;
  do not add unsupported independent artifact evidence.
- `README.md`: replace the stale manual supported-tool sentence with the
  existing catalog/list command as the single live inventory.

## Implementation Sequence

1. Confirm the exact existing BusyBox archive bytes, official HTTPS URL,
   checksum, size, authentication mode, and applicable license notices; place
   the identical reviewed input and a telnet-specific source lock in each
   recipe without changing the BusyBox owner.
2. Implement the x86-64 recipe first. Resolve the minimal configuration, prove
   that only `telnet` is exposed, perform a real build, and reconcile the actual
   link map, static-PIE profile, direct invocation, and loopback negotiation
   test before replicating the recipe shape.
3. Add AArch64, ARMv7, and x86 recipes with the same source, feature surface,
   smoke behavior, and fail-closed checks; vary only OCI platform/triplet,
   architecture/ABI validation, inventory paths, and x86 CPU flags.
4. Warn about expected emulation duration, then run each remaining architecture
   build and target smoke test once through its committed builder digest. Reuse
   BuildKit cache and retained diagnostics for late validation retries.
5. Inspect sizes and hashes, then add all four catalog rows and artifacts,
   update `SHA256SUMS`, `TRUST.md`, and the concise root README, run focused and
   repository-wide validation, and commit/push only this rollout and the moved
   completed-plan record.

## Validation

- Run `bash -n`/`sh -n` on new scripts, `git diff --check`, and inspect tracked
  input/executable modes before any expensive build.
- Verify every tracked source copy against the exact accepted SHA-256 and
  require `SOURCE_AUTHENTICATION=checksum-only` before extraction.
- On x86-64, then each emulated target, run
  `./build.sh telnet <architecture>` and require complete configuration,
  one-applet inventory, final-link evidence, ELF, version/help, and loopback
  negotiation checks before artifact replacement.
- Require candidate/installed SHA-256 equality and re-run the architecture ELF
  validator against each installed output.
- Explicitly stage only the rollout paths so repository validation can inspect
  Git modes, then run `python3 scripts/recipes.py validate`,
  `sha256sum -c artifacts/SHA256SUMS`, and `./validate.sh`.
- Confirm `./build.sh list` shows exactly four `telnet` pairs and that no
  `telnetd`, full BusyBox copy, symlink/wrapper, builder change, utility image,
  root dispatcher change, or generic validation code entered the diff.

## Success Criteria

- `./build.sh telnet <architecture>` rebuilds each committed artifact solely
  from its tracked BusyBox source and the existing immutable builder.
- Every artifact is a stripped static PIE for its promised host architecture,
  directly behaves as BusyBox telnet 1.38.0, and passes the bounded target
  loopback protocol test.
- The public feature boundary is client-only and the READMEs clearly warn that
  telnet is plaintext and not an SSH replacement.
- The rollout adds exactly four recipe owners and artifacts without duplicating
  the broad BusyBox artifact, enabling `telnetd`, changing builders, or adding
  a shared abstraction.

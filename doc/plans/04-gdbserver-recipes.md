# Plan: Add GDBserver Recipes for Both Architectures

## Summary

Replace the legacy x86-64 gdbserver and add an AArch64 counterpart using two
conventional recipes for GDBserver 16.3. Both consume the expanded immutable
architecture builders and independently retained copies of the same
checksum-locked, PGP-authenticated GNU release. Each one-command build validates
a temporary static executable and a real remote-serial-protocol exchange before
replacing its architecture's artifact.

This plan depends on `01-multi-architecture-recipe-selection.md`,
`02-narrow-tcpdump-assurance-selection.md`, and
`03-expand-reusable-builders.md`.

## Problem

`artifacts/x86_64/gdbserver` reports version 16.3 and is a static x86-64 ELF,
but it has no source lock, build recipe, license inventory, or functional build
evidence. There is no `artifacts/aarch64/gdbserver`. The repository therefore
cannot rebuild the existing utility or offer the same remote-debugging tool on
both supported architectures.

## Scope

In scope:

- Preserve GDBserver 16.3 rather than combine provenance repair with an
  upstream upgrade.
- Add enabled `gdbserver/aarch64` and `gdbserver/x86_64` catalog rows and full
  conventional recipe directories.
- Retain `gdb-16.3.tar.xz` (SHA-256
  `bcfcd095528a987917acf9fff3f1672181694926cc18d609c99d0042c00224c5`),
  its GNU detached signature, and a minimal keyring for fingerprint
  `F40ADB902B24264AA42E50BF92EDB04BFF325CF3` in each recipe.
- Build only gdbserver and its required in-tree support libraries as stripped
  static `ET_EXEC` executables with a complete final-link archive inventory.
- Test version output and a bounded remote-debug protocol interaction on the
  target architecture before installing each artifact.
- Replace the existing x86-64 artifact and add the AArch64 artifact, checksum
  records, notices, and concise user/trust documentation.

Out of scope:

- Upgrading to GDB 17.x, changing the existing AArch64 full GDB recipe, or
  building another GDB component.
- Enabling Python, Guile, debuginfod, source-highlight, simulators, or a target
  cross-debugger in gdbserver.
- Exposing gdbserver to a public network during tests or claiming that its
  remote protocol provides authentication or encryption.
- Exact-rebuild qualification, attestation workflow jobs, or an artifact image.

## Design

Create parallel `recipes/gdbserver/{aarch64,x86_64}/` owners using the current
Dockerfile/host-script/guest-script/source-lock/license layout. Keep the source
archive and PGP evidence local to each recipe as required by the existing
validator; identical Git blobs need no shared-source lookup or new fallback
abstraction. Verify the archive checksum again inside the target builder before
extraction.

Configure the GDB 16.3 release for the native musl triplet of each target and
invoke only the gdbserver build targets. Disable unrelated binutils/GDB
front-end, NLS, Python, Guile, debuginfod, Babeltrace, source-highlight,
simulators, and shared libraries through supported configure switches. Capture
the final link with a linker map, reconcile every in-tree and external archive
against exact source or Alpine package/version/license evidence, link with
`-static -no-pie`, install only `/out/gdbserver`, and strip it.

The host entry point follows existing recipe behavior: require Buildx before
pulling or registering emulation, consume only the architecture's committed
builder digest, export to a temporary directory, require the correct ELF
machine and `ET_EXEC`, reject an interpreter, `DT_NEEDED`, debug sections, or a
full symbol table, then run the smoke test in a target-platform container.
Only after all checks does it atomically install mode `0755` to
`artifacts/<architecture>/gdbserver` and report size and SHA-256.

The smoke test checks the exact 16.3 version, starts gdbserver on loopback with
a tiny target program, and uses a bounded minimal Remote Serial Protocol probe
to require a valid connection, stop reply, and clean shutdown. It must use a
random/ephemeral local port, a timeout, and no host/public bind. Document that
gdbserver has no authentication and should be placed behind a trusted transport
rather than exposed directly.

Both source locks use `SOURCE_AUTHENTICATION=pgp`; `TRUST.md` gains the source
evidence and two artifact rows, but both artifacts remain `Not verified` until
a separate native exact-rebuild qualification succeeds. The recipe and trust
documentation must also retain the factual limitation that GNU's valid release
signature uses legacy DSA with SHA-1, matching the existing GDB source record.

## Affected Components

- `recipes/gdbserver/aarch64/*` and `recipes/gdbserver/x86_64/*`: add source
  locks/evidence, Docker builds, host entry points, RSP smoke tests, recipe
  READMEs, reviewed licenses, and linked-archive inventories.
- `recipes/catalog.tsv`: add the two enabled architecture-qualified rows.
- `artifacts/aarch64/gdbserver` and `artifacts/x86_64/gdbserver`: add/replace
  only the validated target executables.
- `artifacts/SHA256SUMS`: add sorted exact records for both outputs.
- `README.md`: present GDBserver 16.3 on both architectures and link its recipe
  instructions without expanding the landing page into a build manual.
- `TRUST.md`: replace the legacy row, add the AArch64 row, record GNU PGP source
  evidence, and retain `Not verified` artifact status.

## Implementation Sequence

1. Download GDB 16.3 and its signature from the recorded GNU HTTPS URLs into
   temporary storage, verify the locked hash and full signer fingerprint, then
   explicitly add the exact evidence and reviewed licenses to each recipe.
2. Implement one architecture recipe, including final-link reconciliation and
   the bounded RSP test; port only architecture constants and triplets to the
   second directory.
3. Run each direct recipe once, warning before an emulated build expected to
   exceed ten minutes, and preserve its build cache/tree until all late
   validation passes.
4. After both candidates pass, add the pair of catalog rows, atomically replace
   the x86-64 artifact, add the AArch64 artifact, and update the sorted manifest
   and bounded documentation.

## Validation

- Verify both tracked archives match the locked SHA-256 and both detached
  signatures validate offline to the exact full fingerprint through
  `python3 scripts/recipes.py validate`.
- Run shell syntax checks, `python3 -m unittest tests.test_recipes`,
  `./build.sh list`, and `git diff --check` before compilation.
- Run `./build.sh gdbserver x86_64` and `./build.sh gdbserver aarch64` once
  each. Confirm target machine, `ET_EXEC`, stripped state, no interpreter, no
  `DT_NEEDED`, exact version 16.3, complete link inventory, and the RSP
  functional exchange.
- Run `sha256sum -c artifacts/SHA256SUMS` and verify the x86-64 legacy hash
  changes only as the intended recipe replacement; inspect both binary sizes
  before committing.
- Confirm the targeted artifact-assurance selector does not rebuild tcpdump for
  these unrelated catalog/manifest additions and that no gdbserver attestation
  claim or GHCR utility image was added.

## Success Criteria

- `./build.sh gdbserver aarch64` and `./build.sh gdbserver x86_64` each rebuild
  the expected committed 16.3 artifact from authenticated tracked source and an
  immutable reusable builder without network source/package resolution.
- Both outputs are stripped static executables for their promised architecture,
  pass the bounded remote-debug protocol test, and have complete source,
  archive, license, checksum, and trust records.
- The old x86-64 no-recipe evidence is gone, while both new artifact statuses
  remain factually `Not verified` pending independent qualification.

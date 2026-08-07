# Plan: Authenticate Source Archives

## Summary

Add optional, explicit upstream authentication to the existing recipe source
locks. Verify the three current archives with their upstream PGP signatures and
full signer fingerprints, while allowing future sources to declare
`checksum-only` when upstream does not provide usable signature evidence. Reuse
the catalog validator as the one source-verification command; do not add a
second trust database or require network access during validation or builds.

Execute this plan after `06-commit-source-inputs.md`, `07-require-buildx.md`,
and `utility-images-01-repository-cleanup.md` are completed. It must complete
before `trust-02-verify-artifacts.md` and before the utility packages are deleted
by `utility-images-02-ghcr-cleanup.md`.

## Problem

The committed SHA-256 values prove that a recipe consumes the bytes selected by
this repository, but the repository controls both those bytes and their hashes.
That does not independently establish that GNU or the Tcpdump Group published
the archives. The current three inputs do have detached upstream signatures:

- GDB 17.2 is signed by fingerprint
  `F40ADB902B24264AA42E50BF92EDB04BFF325CF3`; GDB directs users to the GNU
  keyring at `https://ftp.gnu.org/gnu/gnu-keyring.gpg`.
- tcpdump 4.99.4 and libpcap 1.10.4 are both signed by the Tcpdump Group package
  key with fingerprint `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D`, published
  at
  `https://www.tcpdump.org/release/signing-key-RSA-E089DEF1D9C15D0D.asc`.

The exact recipe-local archives were manually verified against those signatures
during planning, but that evidence is not committed, continuously checked, or
easy for a user to reproduce. At the same time, making signatures mandatory for
every future utility would reject legitimate upstreams that publish only a
release archive and checksum. The valid GDB signature also uses the upstream's
legacy DSA key with SHA-1; it is useful origin evidence for these exact bytes but
must not be presented as cryptographically equivalent to the Tcpdump Group's
RSA/SHA-512 signatures.

## Scope

In scope:

- Commit the three detached signatures and only the two public keys required to
  verify the current archives offline.
- Extend each bounded source record with an explicit authentication mode.
- Make `python3 scripts/recipes.py validate` enforce signatures and exact signer
  fingerprints for `pgp` records while accepting and clearly reporting
  `checksum-only` records.
- Run that existing cheap validation on every pull request under one stable
  `recipe-validation` check name for the later main ruleset.
- Document what each authentication mode proves and show the current source
  status in one user-facing trust document.
- Make future recipe onboarding require an explicit mode rather than silently
  implying authentication from a repository-local checksum.

Out of scope:

- Requiring every future upstream to publish signatures or blocking a recipe
  solely because it is `checksum-only`.
- Supporting signature formats other than detached OpenPGP signatures until a
  real source requires one.
- Keyservers, Web-of-Trust scoring, automated key rotation, revocation polling,
  a custom PKI, or network access during normal validation and builds.
- Claiming that an authentic upstream release is free from vulnerabilities or
  malicious upstream code.
- Adding a signature-algorithm policy engine or rejecting the current GDB source
  solely because its authentic upstream signature uses legacy DSA/SHA-1.
- Changing source versions, source archive bytes, build flags, builders, or
  artifact bytes.

## Design

Keep authentication metadata beside the acceptance metadata in `source.lock`.
Every source record gains `<PREFIX>_AUTHENTICATION`, where the only accepted
values are `pgp` and `checksum-only`. `SOURCE_` remains the primary record and
the existing bounded `LIBPCAP_` record follows the same rule.

For `pgp`, require three additional safe filenames/values:

```text
<PREFIX>_SIGNATURE=<archive>.sig
<PREFIX>_SIGNING_KEY=<recipe-local-key>.gpg
<PREFIX>_SIGNER_FINGERPRINT=<40-uppercase-hex-characters>
```

Derive signature and key paths under the recipe's existing `sources/`
directory. Require both to be tracked, regular, non-symlink files with Git mode
`100644`. Commit a minimal binary OpenPGP keyring containing the exact signing
key rather than the entire GNU keyring or a downloaded key cache. Reusing the
same tcpdump signing-key file from both tcpdump records is intentional.

For `checksum-only`, forbid signature, key, and fingerprint fields for that
record. The archive still must satisfy the existing tracked-file, HTTPS
provenance, and SHA-256 checks. Validation exits successfully but prints a
prominent status such as `checksum-only (upstream signature unavailable or not
adopted)`; this is an acknowledged limitation, not a fallback attempted after a
bad signature.

Extend the existing Python validator rather than creating another manifest or
plugin system. For a PGP record, invoke `gpgv` with the committed keyring,
signature, and archive, consume machine-readable status output, and require the
reported `VALIDSIG` fingerprint to equal the lock exactly. Do not consult a
user keyring, keyserver, environment-selected key, or network URL. A missing
`gpgv`, invalid signature, unexpected signer, missing companion file, or unsafe
field fails closed. The guest build scripts continue verifying SHA-256 only;
the authenticated archive is already fixed by that hash, so adding GnuPG to the
locked builders would add size without another trust guarantee.

Create `TRUST.md` as the single plain-language assurance document. Its source
table identifies every supported source record as `Upstream PGP` or
`Checksum-only`, includes the full fingerprint for signed records, links the
official upstream key/signature location, and explains that authentication
establishes origin rather than safety. Mark GDB's row or adjacent note as legacy
DSA/SHA-1 evidence without weakening or bypassing the exact signature check. The
root README links this document but does not duplicate its table.

The prerequisite cleanup creates `.github/workflows/validate-recipes.yml` with
path-filtered `main` pushes and manual dispatch. Retain those triggers, add an
unfiltered `pull_request` trigger, and give its existing validation job the
stable display name `recipe-validation`. It must report even for documentation-
only pull requests so the later ruleset cannot wait forever on a skipped check;
the job remains Docker-free and inexpensive.

## Affected Components

- `recipes/gdb/aarch64/source.lock`: declare PGP authentication and the exact
  GDB signer fingerprint and companion filenames.
- `recipes/gdb/aarch64/sources/*`: add the GDB detached signature and minimal
  signer keyring without changing the archive.
- `recipes/tcpdump/x86_64/source.lock`: declare PGP authentication separately
  for tcpdump and libpcap using their shared upstream key.
- `recipes/tcpdump/x86_64/sources/*`: add both detached signatures and the one
  minimal Tcpdump Group keyring without changing either archive.
- `scripts/recipes.py`: validate explicit authentication modes, local evidence,
  `gpgv` results, exact fingerprints, and the visible checksum-only status.
- `tests/test_recipes.py`: materially cover both modes, forbidden mixed state,
  missing or unsafe evidence, malformed fingerprints, and unexpected fields.
- `TRUST.md`: add the concise trust model, source-status table, and one existing
  validator command for user verification.
- `README.md`, `AGENTS.md`, and `doc/adding-a-binary.md`: link the trust document
  and make authentication mode an explicit, non-blocking recipe obligation.
- `recipes/{gdb/aarch64,tcpdump/x86_64}/README.md`: identify the committed
  signatures/fingerprints and the source-verification prerequisite.
- `.github/workflows/validate-recipes.yml`: ensure the existing validation job
  runs in an environment with `gpgv`, add the unfiltered pull-request trigger,
  and expose the stable `recipe-validation` check; do not add a second source
  workflow.

## Implementation Sequence

1. Confirm the three prerequisite plans are completed, the source archives
   still match their locked SHA-256 values, and no overlapping recipe work is
   in flight.
2. Download the detached signatures and official key material into a temporary
   directory. Verify the signatures, extract only the two required public keys,
   check their full fingerprints, and add the bounded evidence files under the
   recipe `sources/` directories.
3. Add the explicit authentication fields to both bounded lock shapes and
   extend the validator and focused fixtures without changing archive acceptance
   or build behavior.
4. Add `TRUST.md` and the nearest contract/documentation updates, explicitly
   describing `checksum-only` as accepted but weaker.
5. Add the pull-request trigger and stable job name to the existing fast
   validation workflow without changing its Docker-free command set.
6. Run offline validation with network access disabled, then commit and push
   only this plan's metadata, evidence, validator, tests, workflow prerequisite,
   and documentation changes.

## Validation

- Run `python3 scripts/recipes.py validate`,
  `python3 -m unittest tests.test_recipes`, `./build.sh list`, Python compilation,
  workflow YAML parsing, and `git diff --check`.
- Confirm validation reports three PGP-authenticated source records and no
  checksum-only current record.
- Run validation without a user GnuPG home and without network access; require
  all three signatures to verify only through their committed keyrings.
- Inspect machine-readable `gpgv` status and require the GDB and Tcpdump Group
  fingerprints above exactly; short key IDs or key names are insufficient.
- Confirm the trust table acknowledges GDB's DSA/SHA-1 signature while the
  Tcpdump Group signatures use RSA/SHA-512; do not turn that disclosure into a
  fallback after verification failure.
- Exercise a documentation-only pull request and require `recipe-validation` to
  report and pass without Docker; retain the existing path-filtered `main` push
  behavior.
- In isolated fixtures, prove a corrupt archive, corrupt signature, substituted
  key, wrong fingerprint, missing evidence file, symlink, untracked file, and
  non-`100644` mode each fail.
- Prove a fixture with `AUTHENTICATION=checksum-only` and no PGP fields passes
  checksum validation while printing the documented limitation, and prove that
  leftover PGP fields in that mode fail.
- Compare all three archive hashes and artifact hashes before and after; require
  no changes.

## Success Criteria

- A user can run the existing catalog validation command offline and verify that
  every current source archive carries a valid signature from the exact pinned
  upstream fingerprint.
- Future unsigned sources are accepted only with an explicit `checksum-only`
  declaration that is visible in validation output and `TRUST.md`.
- Source authentication uses committed evidence and direct actual-state checks,
  with no keyserver, custom trust service, network build dependency, or new
  signature abstraction.
- GDB's accepted but legacy upstream signature is visible rather than silently
  receiving the same cryptographic-strength implication as the Tcpdump Group
  signatures.
- Every pull request receives the stable, cheap `recipe-validation` check needed
  by the later protected-main ruleset.
- Current source archives, builders, build behavior, and artifacts are
  unchanged.

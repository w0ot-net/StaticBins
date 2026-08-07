# Plan: Verify and Attest Repository Artifacts

## Summary

Give users a short, honest way to check repository binaries: verify a committed
SHA-256 manifest, rebuild supported artifacts through their existing locked
recipes, and publish GitHub artifact attestations only when the rebuilt bytes
exactly match the committed files. Treat byte mismatch as evidence to classify,
not a reason to make broad reproducibility changes. Artifacts without exact
rebuild evidence remain distributable only with an explicit `Not verified`
status in `TRUST.md`.

Execute this plan after `trust-01-authenticate-sources.md` and after
`utility-images-01-repository-cleanup.md`. It must complete before
`trust-03-protect-main.md` establishes required check names and before
`utility-images-02-ghcr-cleanup.md` deletes the older utility-image provenance.

## Problem

The build scripts validate architecture, static linkage, stripping, versions,
linked inputs, and focused behavior, but those checks do not prove that a
committed binary was produced by the visible recipe. The repository does not
currently claim or test byte-for-byte reproducibility, raw files under
`artifacts/` have no signed build provenance, and users have no single checksum
manifest or verification instructions. The legacy x86-64 files have even less
evidence and must not inherit the assurance language for GDB and tcpdump.

The existing utility-image workflow emits OCI SBOM/provenance, but the ordered
repository cleanup deliberately retires those images. Raw-artifact assurance
must replace that trust surface before the utility packages themselves are
deleted.

## Scope

In scope:

- Perform a bounded reproducibility check for the current GDB and tcpdump
  artifacts using their existing source archives, locked builders, Buildx host
  commands, and target tests.
- Commit one deterministic SHA-256 manifest covering every file currently under
  `artifacts/`, including explicitly unverified legacy files.
- Add one workflow that rebuilds only artifacts approved for exact verification,
  compares their bytes with the committed files, and attests the exact files on
  protected `main` pushes.
- Give the workflow one stable, always-reported assurance gate suitable for the
  later branch ruleset without compiling on documentation-only changes.
- Extend `TRUST.md` with artifact-level status and two short user verification
  commands.
- Permit an artifact to remain `Not verified` when exact rebuild evidence is
  unavailable, without presenting validation or a checksum as provenance.

Out of scope:

- Reintroducing utility containers or GitHub Releases as binary distribution.
- Custom signing keys, a custom transparency log, standalone Sigstore policy,
  SLSA certification, or a second artifact hosting service.
- Making arbitrary future projects reproducible, adding a general build graph,
  or automatically treating every catalog row as attested.
- Chasing nondeterminism beyond one bounded confirmation build or redesigning a
  toolchain solely to earn a stronger label.
- Vulnerability scanning, malware scanning, source review claims, SBOM
  replacement, or assertions that an attested binary is inherently safe.
- Removing legacy artifacts; their required outcome here is an unambiguous
  status, not migration.

## Design

Use a two-result assurance model in `TRUST.md`:

- `Exact rebuild + GitHub attestation`: a clean native rebuild passed the full
  recipe checks and produced the committed SHA-256 exactly; the repository's
  workflow attested that same file.
- `Not verified`: no exact rebuild-and-attestation claim is available. A listed
  checksum still detects download corruption but does not establish provenance.

Do not invent intermediate badges such as "mostly reproducible". Source
authentication remains a separate column so a future artifact may truthfully
show an exact build from `checksum-only` source.

Create `artifacts/SHA256SUMS` with sorted repository-relative paths and lowercase
SHA-256 values for every artifact except the manifest itself. Extend the existing
repository validator to require one exact row per regular artifact, reject
duplicates, unsafe paths, extra rows, stale hashes, and omissions, and preserve
the existing executable Git-mode checks. The manifest is a convenient integrity
index, not a signature or trust root.

Establish initial exact-build status conservatively. Run one clean native
Buildx rebuild of each current supported artifact and compare it with the
committed file. If it matches, no second build is needed. If it differs, run
exactly one additional clean build:

- If the two new candidates match each other, fully validate that canonical
  output and replace the stale committed artifact in a separate explicit commit,
  then require the assurance workflow to reproduce it.
- If the two candidates differ, retain the original artifact, label it `Not
  verified`, omit it from attestation, and record the hashes and bounded result.
  Deterministic-build remediation requires a later, separately scoped decision.

Add `.github/workflows/verify-artifacts.yml` after utility-image publication has
been retired. On every pull request it has a lightweight change-detection job
and an always-reported `artifact-assurance` gate. For changes to verified
artifact bytes, their recipes, source evidence, builder locks, the checksum
manifest, validator, or this workflow, run the explicit current-tool matrix on
the existing native architecture runners. Each job records the committed hash,
runs the supported root build command, requires the installed result to retain
that hash, and therefore reuses all recipe-owned validation. The gate fails when
a required build fails and passes without compilation when no trust-critical
path changed.

On a push to `main`, repeat the same exact comparison and use GitHub's native
artifact-attestation action, pinned by full commit SHA, to attest each verified
raw artifact. Grant only `contents: read`, `id-token: write`, and
`attestations: write`; do not request package write access. Pull-request jobs
never publish attestations. Do not attest a merely pre-existing file without a
successful same-job rebuild comparison.

Keep the verified tool list explicit in the workflow. Adding a future artifact
does not automatically receive provenance: its contributor either demonstrates
an exact rebuild and adds a bounded job or records `Not verified` in `TRUST.md`.
This small explicit list is preferable to a new assurance manifest or generic
build orchestration layer for two real consumers.

Document the normal user path:

```sh
sha256sum -c artifacts/SHA256SUMS
gh attestation verify artifacts/aarch64/gdb --repo w0ot-net/static_bins
```

The trust document explains that the first command checks repository/download
integrity, while the second binds exact bytes to the named GitHub repository,
commit, and workflow. It also states that provenance is not a malware or
vulnerability guarantee.

## Affected Components

- `artifacts/SHA256SUMS`: add the deterministic integrity manifest for every
  distributed file.
- `artifacts/{aarch64/gdb,x86_64/tcpdump}`: update only if two fresh candidates
  agree and prove that the existing committed artifact is stale.
- `.github/workflows/verify-artifacts.yml`: add path-aware exact rebuild checks,
  a stable assurance gate, and push-only raw artifact attestations.
- `scripts/recipes.py`: validate complete and exact artifact-manifest coverage.
- `tests/test_recipes.py`: materially cover manifest completeness, safe paths,
  duplicates, extra entries, and stale hashes.
- `TRUST.md`: add artifact statuses, attestation meaning, legacy limitations,
  and the two-command user verification path.
- `README.md`: link the verification commands without claiming every artifact
  has equal assurance.
- `AGENTS.md` and `doc/adding-a-binary.md`: require explicit trust status for a
  new artifact and forbid attestation without exact same-job rebuild equality.

## Implementation Sequence

1. Confirm source authentication and utility publication cleanup are complete,
   record all existing artifact hashes/modes, and verify the utility packages
   remain available until replacement assurance is established.
2. Run the bounded initial native rebuild comparison for GDB and tcpdump.
   Classify each result using only the two statuses above; announce any build
   expected to exceed ten minutes.
3. Add and validate `artifacts/SHA256SUMS`, including every legacy file without
   implying provenance.
4. Add the exact-rebuild workflow for only the tools that qualified, using
   stable check names and push-only attestations. If neither tool qualifies,
   stop and revise the assurance goal rather than publishing empty provenance.
5. Extend `TRUST.md` and the nearest repository/contributor contracts with the
   verified and unverified results and user commands.
6. Push the bounded changes, require the assurance gate to pass, verify each
   resulting attestation against a freshly downloaded raw file, and record the
   workflow run and hashes.

## Validation

- Run `python3 scripts/recipes.py validate`,
  `python3 -m unittest tests.test_recipes`, `./build.sh list`, workflow YAML
  parsing, shell syntax checks, and `git diff --check`.
- Run `sha256sum -c artifacts/SHA256SUMS` from the repository root and prove the
  validator rejects a missing artifact, omitted row, duplicate row, unsafe path,
  extra row, and one-byte artifact or manifest corruption.
- For each proposed verified tool, run its root build on the native target
  runner, require all recipe checks, and compare the final SHA-256 with the
  committed file. Exercise the one-extra-build limit only after a mismatch.
- Exercise the workflow on a documentation-only pull request and require the
  stable gate to pass without Docker or compilation. Exercise each trust-critical
  path class and require the appropriate exact-build job plus gate.
- Confirm pull-request jobs cannot write attestations or packages. On `main`,
  inspect the attestation subject digest and workflow/commit identity, then run
  `gh attestation verify` against independently downloaded GDB and tcpdump files
  only when their status is verified.
- Confirm every unverified legacy artifact is present in the checksum manifest
  and plainly marked `Not verified`, with no attestation or reproducibility
  claim.

## Success Criteria

- Every distributed file has a convenient checked SHA-256, and users are told
  that this proves integrity rather than provenance.
- Every artifact labeled `Exact rebuild + GitHub attestation` is rebuilt to the
  committed bytes before the exact file is attested by the repository workflow.
- Any artifact lacking exact evidence remains available only with a clear `Not
  verified` status; missing assurance does not block future code or get hidden.
- Users can verify a qualified raw artifact with one checksum command and one
  standard GitHub CLI command, without a release, utility container, custom key,
  or project-specific verification service.
- The workflow exposes one stable required check and avoids expensive builds for
  changes outside the trust boundary.

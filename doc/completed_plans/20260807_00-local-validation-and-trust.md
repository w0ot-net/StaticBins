# Plan: Replace CI Validation with a Local Trust Contract

*Distilled: 2026-08-07*

## Summary

Make one root `./validate.sh` command the repository's fast, offline validation
entry point and remove the recipe-validation and artifact-assurance workflows.
Accept artifacts after their locked recipe has built and validated them on the
target architecture, including through QEMU, and replace the ambiguous binary
trust status with factual build-validation and independent-evidence records.
Preserve the historical tcpdump rebuild attestation as supplemental evidence.

## Problem

The repository currently spreads fast checks across one workflow, exact
rebuild and attestation logic across another, and contributor instructions
across several documents. Those workflows are advisory rather than branch
gates, and the maintainer's stated threat model does not need an independent
GitHub runner to defend against the workstation that produces and pushes the
artifacts. The resulting `Not verified` label also obscures the useful fact
that an artifact passed its recipe-owned source, link, ELF, architecture, and
functional checks.

Keeping runners for checks that can be performed directly adds another
execution environment and policy surface without changing what may reach
`main`. The same problem will recur for every new emulated architecture unless
the repository makes its local validation boundary explicit.

## Scope

In scope:

- Add one non-interactive root command for the existing offline catalog,
  source-evidence, artifact-manifest, unit, dispatcher, and tracked-shell syntax
  checks.
- Delete the recipe-validation and artifact-assurance workflows and remove
  their stable-job-name, native-qualification, and future attestation
  requirements from the live repository contract. Retain pinned Actions
  references while the separate builder-publication workflow still exists.
- Treat native and Buildx/QEMU target execution as equivalent supported ways to
  satisfy each recipe's architecture-specific smoke-test boundary.
- Replace the two-value artifact status in `TRUST.md` with separate factual
  build-validation and independent-evidence columns for every existing
  artifact.
- Preserve the x86-64 tcpdump exact-rebuild attestation, its verification
  command, and the recorded GDB mismatch as historical evidence.
- Update the closest contributor, build, artifact, trust, automation, and user
  authorities to describe the local contract.

Out of scope:

- Replacing the builder-publication workflow; the independent local builder
  publication plan owns that migration.
- Rebuilding or changing any artifact, recipe, source archive, catalog row,
  checksum, builder, or environment lock.
- Deleting the existing tcpdump attestation from GitHub, issuing new
  attestations, adding signing keys, or claiming that a checksum proves who
  built a file.
- Changing the protected `main-history` ruleset or adding a new merge gate.

## Design

Add an executable `validate.sh` at the repository root. It checks its required
local tools, runs `python3 scripts/recipes.py validate`, runs
`python3 -m unittest tests.test_recipes`, confirms `./build.sh list`, and
syntax-checks every tracked shell script according to its interpreter. The
Python validator remains the single owner of catalog, tracked-source,
authentication, file-mode, builder-lock, and exact artifact-manifest
invariants; the wrapper composes existing checks rather than duplicating their
logic. It performs no Docker setup and compiles no utility.

Delete `.github/workflows/validate-recipes.yml` and
`.github/workflows/verify-artifacts.yml`. Do not replace them with hooks,
generated status files, workflow shims, or a second validation implementation.
The maintainer runs `./validate.sh` before committing and pushing, while a
recipe or builder change additionally runs its narrow real build and target
smoke test. Direct validation of the checked-out bytes is the acceptance
record; a post-push status is not required.

Reshape the artifact table in `TRUST.md` around three orthogonal facts:

- source authentication remains `Upstream PGP` or `Checksum only`;
- build validation records that the maintainer built the artifact through its
  committed recipe and passed that recipe's target checks;
- independent evidence records `None`, the historical tcpdump exact native
  rebuild and GitHub attestation, or the historical GDB mismatch.

Historical evidence remains accurate after its workflow file is deleted. Keep
the signer workflow identity as literal historical text in the GitHub CLI
verification command rather than linking to a path that no longer exists.
Explain that the attestation identifies that past workflow execution; it is
not the current artifact acceptance mechanism.

## Affected Components

- `validate.sh`: add the single local fast-validation entry point.
- `.github/workflows/validate-recipes.yml`: delete the redundant hosted
  validation path.
- `.github/workflows/verify-artifacts.yml`: delete runner selection, exact
  rebuild, comparison, attestation, and aggregate assurance logic.
- `AGENTS.md`: require the local command and recipe-owned target validation;
  remove stable validation job names, native qualification, and mandatory
  trust labels while retaining the pin rule for the remaining publication
  workflow.
- `README.md`: point users and maintainers to local integrity/trust checks
  without implying that un-attested artifacts skipped recipe validation.
- `TRUST.md`: replace status labels with factual build and independent-evidence
  records while preserving historical tcpdump and GDB evidence.
- `doc/adding-a-binary.md`: make local validation, the direct recipe build,
  manifest update, and factual TRUST row the complete contribution procedure.
- `doc/architecture/README.md`: remove GitHub attestation from the normal
  manufacturing diagram.
- `doc/architecture/build/BUILD_PIPELINE.md`: identify `./validate.sh` as the
  separate repository-state validation path.
- `doc/architecture/artifacts/ARTIFACT_CONTRACT.md`: make recipe-owned target
  validation the acceptance boundary and independent rebuilds optional facts.
- `doc/architecture/trust/TRUST_CHAIN.md`: remove artifact-attestation Actions
  as a required trust link, retain the temporary builder-publication boundary,
  and describe historical independent evidence separately.
- `doc/architecture/trust/AUTOMATION_AND_GOVERNANCE.md`: replace validation
  workflow roles with local command ownership, accurately retain the separate
  builder workflow, and preserve the protected-history boundary.

## Implementation Sequence

1. Add `validate.sh` as a thin composition of the checks already executed by
   the validation workflow, and run it before changing the live contract.
2. Update `AGENTS.md` and the owning architecture pages together so local
   recipe validation, QEMU acceptance, and optional independent evidence are
   unambiguous.
3. Rewrite the live README, contributor procedure, and TRUST artifact table;
   retain the exact historical hashes and attestation verification identity.
4. Delete the two validation/assurance workflows, run the new local command,
   inspect the complete diff for stale references, then commit and push only
   the planned paths.

## Validation

- Run `bash -n validate.sh`, then run `./validate.sh` from the repository root.
- Run `git diff --check` and inspect `git ls-files -s` for executable mode on
  `validate.sh`.
- Search live files outside completed, abandoned, and active plan records for
  `recipe-validation`, `artifact-assurance`, `validate-recipes.yml`,
  `verify-artifacts.yml`, `Not verified`, mandatory native qualification, and
  live attestation-workflow instructions; only deliberate historical TRUST
  evidence may remain.
- Confirm `.github/workflows/publish-builder.yml` is the only remaining
  workflow, every `uses:` reference is still pinned, and its replacement
  belongs to the next plan.
- Confirm no artifact, recipe, source archive, catalog row, manifest entry,
  builder file, or environment lock changed.

## Success Criteria

- `./validate.sh` performs all fast repository checks locally and succeeds on a
  clean checkout without Docker or network access.
- No hosted workflow validates or rebuilds utility artifacts, and the live
  contract contains no stable CI-job or future attestation requirement.
- Every artifact has a factual source, recipe-validation, and independent-
  evidence record; the tcpdump attestation and GDB mismatch remain accurately
  documented as history.
- Native and QEMU target execution satisfy the same architecture-specific
  artifact contract.

## Execution Notes

Completed on 2026-08-07 in implementation commit
`4a074dff723156e46e0ef5a624f26c45f67dd971`.

- Added executable root `validate.sh`, which checks its local prerequisites and
  composes offline recipe validation, focused unit tests, dispatcher listing,
  and interpreter-appropriate syntax checks for every tracked shell script.
- Deleted the hosted recipe-validation and artifact-assurance workflows. The
  builder-publication workflow remains temporarily and all four of its Actions
  references remain pinned to full commit SHAs.
- Updated the contributor and architecture authorities to make recipe-owned
  native or QEMU target validation the acceptance boundary. No artifact,
  recipe, source, catalog, checksum, builder, or environment-lock file changed.
- Replaced `TRUST.md` status labels with source-authentication,
  build-validation, and independent-evidence columns. The literal historical
  tcpdump signer identity, reproduced SHA-256, and GDB mismatch are preserved.
- There were no material deviations from the accepted plan.
- `bash -n validate.sh`, `./validate.sh`, `git diff --check`, executable-mode
  inspection, stale-reference searches, remaining-workflow enumeration, and
  full-SHA Actions-reference checks all passed before the implementation
  commit and push.

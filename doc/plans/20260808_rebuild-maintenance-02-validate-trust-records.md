# Plan: Validate Artifact Trust Records

## Summary

Make the existing artifact table in `TRUST.md` part of offline repository
validation. Parse that table directly, require one row for every catalog-backed
artifact, and compare a canonical source-authentication summary with the
generic source records produced by the validator. Do not add a second trust
manifest or attempt to machine-verify narrative evidence.

## Problem

The repository contract requires `TRUST.md` to record source authentication,
recipe build validation, and independent evidence for every distributed
artifact, but `./validate.sh` does not inspect those records. A catalog or
artifact change can therefore pass while its table row is missing, duplicated,
stale, or inconsistent with `source.lock`. The current prose labels also do not
form a deterministic representation for tools with multiple sources.

## Scope

In scope:

- Parse the existing four-column Markdown table under `## Artifact records`.
- Require its artifact paths to match the validated recipe output set exactly,
  with no missing, extra, duplicate, or out-of-order rows.
- Derive and require a canonical source-authentication cell from each recipe's
  ordered `SourceAuthentication` records.
- Require an explicit build-validation value and an explicit independent-
  evidence value for every row, preserving the current factual evidence.
- Add the trust-table check to the existing `scripts/recipes.py validate` path
  and document the enforced format.

Out of scope:

- Adding a TSV, JSON, or other sidecar as a new trust source of truth.
- Validating the narrative source table, historical attestation prose, or the
  truth of independent rebuild claims.
- Creating attestations, rebuilding artifacts, or changing the trust model.
- Enforcing GitHub review or status-check policy.

## Design

Implement a focused parser for the artifact-record section of `TRUST.md` in
the existing catalog validator. Locate one exact table header and separator,
accept only its four cells, normalize the backticked artifact path, and stop at
the end of that contiguous table. Fail on a missing or repeated table, malformed
rows, blank cells, duplicate artifact paths, or paths outside the conventional
catalog outputs. Require rows in lexical artifact-path order so the file has
one deterministic representation.

Represent source assurance from actual validated state rather than introducing
another model. For each `Recipe.source_authentications` entry, emit
`<name>=<mode>` in its existing deterministic order and join multiple entries
with `; `, for example `source=pgp` or `source=pgp; libpcap=pgp`. Migrate the
current human labels in the artifact table to that canonical syntax. Require
the build-validation cell to remain the exact repository statement
`Committed recipe and target checks passed`; require the independent-evidence
cell to be nonempty but leave its factual text human-maintained.

Run the trust check only after catalog rows, source records, recipe outputs, and
the artifact manifest have validated, so its expected set and authentication
summary come from trusted in-memory `Recipe` values. This plan therefore
depends on `20260808_rebuild-maintenance-01-generic-source-records.md`; it must
not reproduce source-prefix logic in the Markdown parser.

## Affected Components

- `scripts/recipes.py`: parse and validate the artifact trust table against the
  loaded recipes as part of the existing validation command.
- `tests/test_recipes.py`: extend the repository fixture with trust records and
  cover missing, extra, duplicate, unordered, malformed, blank, and
  authentication-mismatch failures.
- `TRUST.md`: convert source-authentication cells to the canonical derived
  syntax while preserving all build and independent-evidence facts.
- `doc/architecture/trust/TRUST_CHAIN.md`: describe the artifact-table
  consistency check and its limits.
- `doc/adding-a-binary.md`: specify the exact trust row that accompanies a new
  catalog artifact.

## Implementation Sequence

1. Complete the generic source-record plan so every recipe exposes all of its
   authentication records without tool-specific knowledge.
2. Add a canonical authentication formatter and strict artifact-table parser
   to `scripts/recipes.py`, then compare the table with the validated recipes.
3. Update test fixtures and add focused positive and negative table cases,
   including a multi-source recipe.
4. Migrate all existing artifact rows in `TRUST.md` mechanically and update
   the nearest authority and onboarding instructions.

## Validation

- Run `python3 -m unittest tests.test_recipes` and confirm each malformed table
  case fails for its intended reason.
- Run `python3 scripts/recipes.py validate` and confirm all 24 artifact rows
  match their catalog outputs and source locks.
- Temporarily exercise, through tests rather than worktree edits, one missing
  row, one extra row, one authentication mismatch, and one two-source record.
- Run `./validate.sh` and `git diff --check`.
- Inspect the `TRUST.md` diff to confirm independent-evidence text was not
  weakened or replaced.

## Success Criteria

- Offline validation fails unless `TRUST.md` has exactly one deterministic
  artifact record for every validated catalog output and no other artifact.
- Each source-authentication cell is mechanically consistent with all source
  records in the corresponding recipe lock.
- Every row explicitly records build validation and independent evidence.
- Existing narrative evidence remains human-owned, and no duplicate trust
  manifest or artifact rebuild is introduced.

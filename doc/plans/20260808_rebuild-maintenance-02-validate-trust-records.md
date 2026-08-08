# Plan: Derive Artifact Trust Records from Validated State

## Summary

Remove the redundant 24-row artifact ledger from `TRUST.md` instead of adding a
Markdown parser to keep it synchronized. Validate the real artifact-to-recipe
mapping in the existing manifest validator, state common trust facts once, and
retain only exceptional independent evidence. The result adds only one small
set comparison to production code and deletes substantially more documentation
than it adds.

## Problem

The artifact table repeats catalog paths, source authentication already owned
by `source.lock`, the same build-validation sentence 24 times, and mostly
`None` evidence cells. Parsing that prose would create a new schema and a large
test surface solely to police duplicated state. The actual missing invariant is
simpler: every distributed artifact must correspond to a validated catalog
recipe.

## Scope

In scope:

- Require the artifact paths validated by `artifacts/SHA256SUMS` to equal the
  output paths derived from `recipes/catalog.tsv`.
- Replace the repetitive artifact table with set-wide source/build statements
  and a short table containing only artifacts with independent evidence.
- State explicitly that an artifact absent from the exception table has no
  independent evidence.
- Align contributor and trust-contract documentation with the derived model.

Out of scope:

- Parsing Markdown in repository validation or adding a trust sidecar.
- Changing the source-record table, authentication rules, build-validation
  standard, or factual evidence.
- Rebuilding artifacts, creating attestations, or changing GitHub policy.

## Design

Pass the set of `Recipe.output` values from `load_catalog` into the existing
artifact-manifest validator. That function already enumerates every actual
artifact and checks manifest coverage, file mode, and digest; add one direct set
comparison so an artifact without a catalog recipe, or a recipe output absent
from the artifact set, fails in the same aggregated error report. Do not create
a trust parser, formatter, or new data class.

In `TRUST.md`, explain the conventional mapping from each manifest path to its
catalog recipe and validated `source.lock`. Record once that every distributed
artifact passed its committed recipe and target checks. Replace the four-column
per-artifact table with an exception-only independent-evidence table preserving
the current AArch64 GDB mismatch and x86_64 tcpdump evidence verbatim, followed
by a statement that all unlisted artifacts have none. This records the same
facts without duplicating source modes and defaults for every architecture.

Update the repository contract and onboarding text to require the set-wide
statement plus factual exceptions, not one copied row per artifact. This plan
follows the generic source-record plan so the derived artifact-to-source mapping
remains generic for future multi-source recipes.

## Affected Components

- `scripts/recipes.py`: compare manifest artifact paths directly with recipe
  outputs using the sets already available during catalog loading.
- `tests/test_recipes.py`: add one focused case proving a manifest-valid
  artifact without a catalog recipe is rejected.
- `TRUST.md`: delete the repetitive artifact ledger and retain common facts
  plus the two current evidence exceptions.
- `AGENTS.md`: express the compact trust-record contract without requiring
  duplicated per-artifact rows.
- `doc/architecture/artifacts/ARTIFACT_CONTRACT.md`: own the validated
  one-recipe-per-artifact set invariant and compact evidence-record model.
- `doc/adding-a-binary.md`: remove the requirement to copy a default trust row;
  require an update only for a changed common fact or new independent evidence.

## Implementation Sequence

1. After the generic source-record plan, add the artifact/recipe set comparison
   and its single regression case.
2. Compact `TRUST.md` without changing either exceptional evidence record.
3. Align the repository contract, trust authority, and contributor procedure.

## Validation

- Run the focused artifact-manifest unit tests and
  `python3 -m unittest tests.test_recipes`.
- Run `python3 scripts/recipes.py validate` and confirm the 24 catalog outputs
  exactly match the 24 distributed artifacts.
- Run `./validate.sh` and `git diff --check`.
- Inspect the diff to confirm no artifact, checksum, source, or evidence fact
  changed and that the total repository line count decreases.

## Success Criteria

- A distributed artifact without exactly one catalog recipe fails validation.
- Trust facts are derived from validated catalog, manifest, and source-lock
  state rather than copied into a Markdown schema.
- The two current independent evidence records remain factual and visible; all
  other artifacts are explicitly covered by the set-wide default.
- No Markdown parser or trust sidecar exists, and the implementation is a net
  reduction in repository lines.

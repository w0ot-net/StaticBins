# Plan: Validate Source Records Generically

*Distilled: 2026-08-08*

## Summary

Replace the duplicated tcpdump-only source validation with one loop over
prefixed records in the existing `source.lock` format. Reuse the current checks
and data model, preserve every current lock unchanged, and make
`scripts/recipes.py` smaller by deleting the specialized branch.

## Problem

`scripts/recipes.py` validates `SOURCE_*` for every recipe but repeats the same
logic for `LIBPCAP_*` only when the recipe is tcpdump. Another multi-source tool
would require another branch, contrary to the repository rule that conforming
tools must not specialize repository validation.

## Scope

In scope:

- Validate the mandatory `SOURCE_` record and any additional complete prefixed
  records with the same existing invariants.
- Reject incomplete records, unused lock fields, and duplicate archive names.
- Delete the tcpdump condition and replace specialized tests and instructions.
- Preserve deterministic `Recipe.source_authentications` output.

Out of scope:

- A new lock format, source manifest, registry, schema layer, or dependency
  resolver.
- Changes to recipe locks, source bytes, builds, artifacts, or checksums.
- Source deduplication, Git LFS, or shared recipe build machinery.

## Design

Keep `_read_lock`, `SourceAuthentication`, and
`_validate_source_authentication`. Discover records from keys ending in
`_VERSION`: require `SOURCE_`, then process additional prefixes lexically.
For each prefix, one small helper should require and validate the existing six
base fields (`VERSION`, `ARCHIVE`, `SHA256`, `UPSTREAM_URL`, `LICENSE`, and
`AUTHENTICATION`), call the authentication helper, and return the archive name,
authentication result, and consumed fields. After the loop, reject unconsumed
keys; this catches unknown suffixes and authentication fields without a second
classification system.

Track archive names in the loop and reject reuse within a lock. Derive the
existing display name directly from the prefix (`SOURCE_` becomes `source` and
`LIBPCAP_` becomes `libpcap`). Do not add a prefix registry or compatibility
path.

The production diff must remove more validator code than it adds. If the
helper and loop do not produce a net reduction in `scripts/recipes.py`, simplify
the implementation before accepting it; correctness tests and documentation
are not a reason to retain the duplicated branch.

## Affected Components

- `scripts/recipes.py`: replace primary/tcpdump duplication with the helper and
  loop while retaining current validation behavior.
- `tests/test_recipes.py`: replace tcpdump-specific setup with focused generic
  single- and multi-source cases and failure cases for incomplete, unused, or
  duplicate-archive records.
- `doc/architecture/build/SOURCE_INPUTS.md`: state the generic prefixed-record
  invariant.
- `doc/adding-a-binary.md`: remove the instruction to specialize validation for
  another source.

## Implementation Sequence

1. Extract the repeated per-record checks, loop over `SOURCE_` plus discovered
   prefixes, and delete the tcpdump branch.
2. Replace specialized tests with the smallest cases that prove arbitrary
   prefixes, both authentication modes, rejection of bad records, and stable
   ordering.
3. Align the source authority and contributor procedure with the generic rule.

## Validation

- Run `python3 -m unittest tests.test_recipes`.
- Run `python3 scripts/recipes.py validate` against all 24 current recipes.
- Run `./validate.sh` and `git diff --check`.
- Inspect `git diff --stat -- scripts/recipes.py` and confirm production
  validator lines decrease and no recipe or artifact files changed.

## Success Criteria

- No validator branch names tcpdump or `LIBPCAP_`.
- Any complete prefixed record receives the current source and authentication
  checks; incomplete, unused, or archive-aliasing fields fail clearly.
- Every current lock validates without migration or rebuild.
- `scripts/recipes.py` is smaller than before the implementation.

## Execution Notes

- Implemented one `_validate_source_record` helper and a deterministic prefix
  loop; removed the tcpdump/`LIBPCAP_` validator branch.
- Replaced the specialized fixture with arbitrary multi-source coverage and
  updated the source-input authority and contributor procedure.
- No material deviations were required. Source locks, recipes, artifacts,
  checksums, and unrelated static-PIE/builder work were not changed.
- Validation passed with `python3 -m unittest tests.test_recipes`,
  `python3 scripts/recipes.py validate`, `./validate.sh`, and
  `git diff --check`. All 24 recipes and 25 tests passed.
- `scripts/recipes.py` decreased from 727 to 702 lines.
- Implementation commit: `3f46b14`.

# Plan: Validate Source Records Generically

## Summary

Replace the tcpdump-specific secondary-source branch in repository validation
with generic validation of complete, prefixed source records in each existing
`source.lock`. Keep the current shell-compatible lock format, committed source
layout, and `Recipe.source_authentications` interface; the existing `SOURCE_`
and `LIBPCAP_` records require no migration.

## Problem

`scripts/recipes.py` validates the primary `SOURCE_*` record for every recipe,
but recognizes a second record only when the recipe name is `tcpdump` and its
fields begin with `LIBPCAP_`. Adding another conforming multi-source tool would
therefore require another tool-specific validator branch, contrary to the
repository contract that catalog validation remain generic. The onboarding
guide currently instructs maintainers to extend validation for each bounded
lock shape, preserving that coupling.

## Scope

In scope:

- Discover and validate any complete source-record prefix already expressed in
  a recipe's `source.lock`.
- Preserve all existing checksum, tracked-file, HTTPS, PGP, fingerprint, and
  safe-filename checks for every discovered record.
- Require `SOURCE_` as the primary record, reject malformed or incomplete
  record groups, reject unknown fields, and require distinct archive filenames
  within one lock.
- Return source authentication records in deterministic primary-then-prefix
  order for current and future consumers.
- Replace tcpdump-specific tests and documentation with the generic contract.

Out of scope:

- Changing the `source.lock` file format or adding a separate source manifest.
- Migrating existing recipe locks, source archives, guest build scripts, or
  artifact bytes.
- Turning the catalog into a dependency resolver or centralizing
  recipe-specific configure and build behavior.
- Deduplicating tracked source archives or adopting Git LFS.

## Design

Keep `_read_lock` as the sole parser for the existing `KEY=value` format. Add a
small source-record validation path in `scripts/recipes.py` that groups keys by
the known field suffixes rather than by tool name. A valid record prefix is an
uppercase identifier ending in `_`; `SOURCE_` is mandatory and is always
processed first, while additional prefixes are processed lexically for stable
diagnostics and `Recipe.source_authentications` ordering.

Each prefix must provide exactly the six base fields `VERSION`, `ARCHIVE`,
`SHA256`, `UPSTREAM_URL`, `LICENSE`, and `AUTHENTICATION`. Apply the current
version, digest, HTTPS, archive-path, tracked-mode, and archive-byte checks to
each group. Reuse `_validate_source_authentication` for the two supported
authentication modes: `pgp` requires `SIGNATURE`, `SIGNING_KEY`, and
`SIGNER_FINGERPRINT`, while `checksum-only` forbids those fields. Reject keys
that cannot be assigned to a valid record, partial groups, unsupported suffixes,
and duplicate archive filenames across prefixes.

Derive the authentication display name without adding state: `SOURCE_` remains
`source`, and another prefix becomes its lowercase identifier without the
trailing underscore (`LIBPCAP_` becomes `libpcap`). Remove the `name ==
"tcpdump"` branch after generic validation covers the existing two-record
locks. Error messages should identify the offending prefix or field rather
than a particular tool.

## Affected Components

- `scripts/recipes.py`: discover source-record groups, validate each through
  the existing invariants, enforce archive uniqueness, and remove the
  tcpdump-specific branch.
- `tests/test_recipes.py`: replace special tcpdump fixtures with generic
  one-, two-, and three-record coverage plus malformed-group failures.
- `doc/architecture/build/SOURCE_INPUTS.md`: define the generic prefixed-record
  ownership and validation contract.
- `doc/adding-a-binary.md`: tell maintainers how to add another complete source
  record without specializing repository validation.

## Implementation Sequence

1. Refactor the source-record field definitions and per-record checks in
   `scripts/recipes.py` without changing the public catalog or recipe result.
2. Add generic prefix discovery, deterministic ordering, complete-group and
   archive-uniqueness checks, then delete the tcpdump-only branch.
3. Update focused tests for existing single-source and multi-source success,
   a third arbitrary source, mixed authentication modes, malformed prefixes,
   incomplete or unknown fields, duplicate archives, and stable ordering.
4. Update the source-input authority and onboarding guide to match the generic
   invariant.

## Validation

- Run `python3 -m unittest tests.test_recipes` to exercise success and failure
  fixtures, including the unchanged tcpdump lock shape.
- Run `python3 scripts/recipes.py validate` against all committed recipes and
  confirm all 24 catalog rows still validate.
- Run `./validate.sh` for the complete offline repository check.
- Run `git diff --check` and inspect the diff to confirm no `source.lock`,
  recipe, artifact, or checksum-manifest files changed.

## Success Criteria

- No validator behavior is selected by recipe name or by the literal
  `LIBPCAP_` prefix.
- Any well-formed additional source record receives the same checksum,
  provenance, tracked-file, and authentication validation as `SOURCE_`.
- Partial, unknown, unsafe, or archive-aliasing source records fail with an
  actionable field or prefix diagnostic.
- Every current recipe validates without lock migration or artifact rebuild.

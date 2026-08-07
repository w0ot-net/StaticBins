# Plan: Select Recipes by Tool and Architecture

*Distilled: 2026-08-07*

## Summary

Make `(name, architecture)` the recipe identity so one tool can have both
`aarch64` and `x86_64` recipes without adding catalog fields or tool-specific
dispatch code. Add the explicit public command `./build.sh <tool>
<architecture>`, retain `./build.sh <tool>` only when exactly one enabled row
matches, and make ambiguous requests fail with the available architectures.

## Problem

`scripts/recipes.py` and `build.sh` currently reject a repeated tool name even
when the architecture differs. That prevents the requested eight recipe rows:
each of `gdbserver`, `lsof`, `socat`, and `strace` must exist once for AArch64
and once for x86-64. The current `./build.sh list` output also hides
architecture, so it cannot describe such a catalog.

## Scope

In scope:

- Allow the same validated recipe name on different supported architectures
  while continuing to reject an exact duplicate `(name, architecture)` pair.
- Accept `./build.sh list`, `./build.sh <tool>`, and `./build.sh <tool>
  <architecture>`; preserve one-argument dispatch for currently unique `gdb`
  and `tcpdump` recipes.
- List enabled recipes as deterministic tab-delimited `name` and
  `architecture` pairs.
- Reject unsafe or unsupported architecture arguments, disabled exact rows,
  unknown pairs, and ambiguous one-argument requests before executing a recipe.
- Update focused tests and the nearest public/contributor documentation for the
  new identity and command contract.

Out of scope:

- Adding any of the eight requested recipes or changing existing artifacts.
- Adding an architecture, catalog field, alias, default architecture, or
  interactive selector.
- Changing artifact-assurance selection; the independently executable
  efficiency correction is owned by `02-narrow-tcpdump-assurance-selection.md`.

## Design

Keep the three-field catalog schema. The pair already contains all information
needed to derive `recipes/<name>/<architecture>/build.sh` and
`artifacts/<architecture>/<name>`, so no recipe ID or builder selector is
needed.

`scripts/recipes.py` will track seen pairs instead of seen names. Its diagnostic
source identifier will include architecture so validation output remains
unambiguous when two locks have the same tool and source labels. No source-lock,
artifact-manifest, or architecture validation is weakened.

`build.sh` will validate every catalog row before dispatch. With two arguments
it matches one exact pair. With only a tool name it executes the recipe only
when exactly one enabled row has that name; zero rows is unknown, one disabled
row is disabled, and multiple architecture rows produce an actionable error
that names the explicit commands. `list` remains a one-argument operation and
prints one `name<TAB>architecture` line per enabled catalog row in catalog
order. Architecture values remain restricted to `aarch64` and `x86_64`.

## Affected Components

- `build.sh`: parse the optional architecture, validate pair uniqueness, list
  architecture-qualified rows, and report ambiguous requests.
- `scripts/recipes.py`: use `(name, architecture)` uniqueness and
  architecture-qualified source diagnostics.
- `tests/test_recipes.py`: cover valid repeated names across architectures,
  exact-pair rejection, explicit dispatch, backward-compatible unique
  dispatch, ambiguous errors, listing, and invalid arguments.
- `README.md`, `doc/adding-a-binary.md`, and `AGENTS.md`: document recipe pair
  identity, explicit multi-architecture commands, and the unambiguous shorthand.

## Implementation Sequence

1. Change Python catalog uniqueness and diagnostics, then update fixtures to
   prove two architectures for one name validate while an exact repeated pair
   fails.
2. Update the Bash dispatcher and its subprocess tests for list, exact,
   shorthand, disabled, ambiguous, malformed, and missing-script behavior.
3. Update only the command and catalog-identity contracts in the root,
   onboarding, and agent documentation.

## Validation

- Run `python3 -m unittest tests.test_recipes` and `python3 scripts/recipes.py
  validate`.
- Run `./build.sh list` and require `gdb<TAB>aarch64` and
  `tcpdump<TAB>x86_64`; run both existing one-argument commands through a
  controlled dispatcher fixture without performing real builds.
- In a temporary catalog fixture, prove `tool/aarch64` and `tool/x86_64`
  dispatch explicitly, `./build.sh tool` rejects the ambiguity, and an exact
  duplicate pair is rejected by both validators.
- Run Bash syntax checks for changed shell and `git diff --check`.
- Let the pull request run the one required tcpdump exact rebuild because the
  shared dispatcher changed; do not rerun it locally after the same committed
  bytes pass.

## Success Criteria

- The catalog accepts one row for each supported architecture of the same tool
  and rejects an exact duplicate pair.
- `./build.sh <tool> <architecture>` is deterministic, while the existing
  unique `./build.sh gdb` and `./build.sh tcpdump` commands remain valid.
- Listing exposes architecture and every unsafe, disabled, unknown, or
  ambiguous request fails before a recipe executes.

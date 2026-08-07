# Plan: Centralize Architecture Onboarding

*Distilled: 2026-08-07*

## Summary

Add one minimal builder-architecture catalog that owns the internal identifier,
OCI platform, and public builder-tag prefix shared by generic orchestration.
Make dispatch, catalog validation, and builder publication consume that catalog,
then document the complete publish-before-recipe procedure for adding an
architecture. Keep target ABI, ELF, and functional checks explicit in the
architecture and tool owners rather than generalizing policy that genuinely
differs by target.

Execute this plan after the open ARMv7 artifact plans and the ordered AArch64
tcpdump and x86-64 GDB plans, and before the 32-bit x86 builder and recipe
plans.

## Problem

The repository's high-level formula is consistent, but adding an architecture
requires synchronized code edits in several generic owners. `build.sh` repeats
the architecture allowlist in two cases, `scripts/recipes.py` has another
literal set, and `builders/publish.sh` has a case that separately maps each
identifier to a directory, OCI platform, floating tag, and versioned-tag
prefix. The same current list is then repeated in contributor and architecture
documentation.

This duplication creates drift risk and makes a fourth architecture look like
a dispatcher/validator feature rather than a new instance of an established
contract. The repository also documents how to add a binary only after its
builder exists; it has no single procedure for defining, validating,
publishing, locking, and finally activating a new architecture.

The architecture-specific build scripts contain additional duplication, but
their meaningful differences include runtime identity, ELF class and machine,
endianness, ARM ABI flags, package probes, and target smoke behavior. Folding
those checks into a generic schema would expand this onboarding fix into a
validation-framework rewrite and require rebuilding unrelated artifacts.

## Scope

In scope:

- Add `builders/catalog.tsv` with exactly three fields: internal
  `architecture`, Docker/OCI `platform`, and public builder `tag_prefix`.
- Populate exact rows for `aarch64`, `armv7`, and `x86_64`, preserving the
  existing platforms and the public `x64-*` compatibility prefix.
- Add one shared Bash catalog loader used by the root dispatcher and local
  builder publisher, with fail-closed schema, value, ordering, and uniqueness
  checks.
- Make `scripts/recipes.py` validate the builder catalog and use its
  architecture identities instead of a literal Python allowlist.
- Derive builder directory, floating tag, and versioned-tag prefix in
  `builders/publish.sh` from the selected catalog row.
- Update focused tests for valid, malformed, duplicate, unsorted, unsupported,
  and mismatched builder/catalog state.
- Add one authoritative contributor procedure for adding an architecture and
  update the nearest contracts to point to the catalog rather than repeat a
  code-owned allowlist.

Out of scope:

- Changing, rebuilding, or republishing any current builder or artifact.
- Migrating every recipe host script to read its OCI platform or binfmt target
  from shared metadata; those scripts may change only with their required
  artifact rebuilds.
- Generalizing ELF, ABI, runtime, package/archive, full-system VM, or functional
  smoke validation across architectures or tools.
- Adding a scaffold generator, templating builder directories, or generating
  documentation from the catalog; the documented procedure is sufficient for
  an infrequent architecture bootstrap.
- Adding the planned `x86` row, builder, recipe, or artifact in this plan.
- Changing the recipe catalog's three-field schema or its `(name,
  architecture)` identity.

## Design

Create `builders/catalog.tsv` with this exact schema and initial state:

```text
architecture	platform	tag_prefix
aarch64	linux/arm64	aarch64-
armv7	linux/arm/v7	armv7-
x86_64	linux/amd64	x64-
```

The catalog owns only facts with multiple real generic consumers. Builder
directories remain derived as `builders/<architecture>/`; floating tags become
`<tag_prefix>latest`; the selected `BUILDER_TAG` must start with
`<tag_prefix>`. Do not add binfmt names, runtime machines, ELF strings, package
sets, or enabled state: those values either have architecture-specific
validation owners or are unnecessary. Every row represents a supported
builder architecture, including a published builder that has no recipe yet.

Require a literal header, one nonblank tab-delimited row per architecture,
ASCII safe values, sorted unique identifiers, and unique tag prefixes.
Architecture identifiers follow the repository's existing safe
lowercase identifier syntax. Platforms must be normalized `linux/<arch>` or
`linux/<arch>/<variant>` values with no path traversal or shell syntax. Tag
prefixes must be lowercase registry-tag-safe values ending in `-`. Each current
row must resolve to a regular `builders/<architecture>/` containing a regular
Dockerfile, package lock, environment lock, and executable candidate command;
the environment lock must retain its immutable image requirements and its
`BUILDER_TAG` must match the catalog prefix.

Add `scripts/builder-catalog.sh` as the single Bash parser. Loading the catalog
validates every row and exposes associative mappings for platform and tag
prefix. `build.sh` sources it, validates the builder catalog before reading
recipe rows, and accepts a recipe architecture only when a corresponding
builder row exists. `builders/publish.sh` sources the same helper, safely
derives the selected builder directory, platform, versioned-tag prefix, and
floating tag, and preserves all current non-replacement, candidate validation,
Buildx, SBOM, provenance, and digest-inspection behavior. Unknown identifiers
must fail before Docker checks or registry access.

Keep Python as the deeper repository validator. Replace the literal
`ARCHITECTURES` set with a strict builder-catalog loader and use its keys while
validating recipe rows. Validate all cataloged builder owners even when an
architecture has no recipe, so a builder-only foundation cannot silently carry
an incomplete lock or missing conventional file. Do not make shell dispatch
depend on Python or add Python to the ordinary artifact-build prerequisites.

Focused tests should establish parity between both consumers rather than copy
the production rows into test assertions. A fixture may write a minimal valid
builder catalog, but tests must prove malformed headers/rows, unsafe values,
duplicates, unsorted identifiers, missing builder files, a tag-prefix mismatch,
an unknown recipe architecture, and an unknown publisher argument all fail.
One regression assertion should require the real catalog rows to map to the
three current platforms and prefixes exactly.

Add `doc/adding-an-architecture.md` as the task authority. Its sequence is:
define a precise host ABI and internal identifier; add the builder catalog row
and conventional builder owner; pin base/binfmt/package inputs; implement and
run target-specific runtime and static ELF probes; publish a new non-replaceable
builder; inspect and commit its immutable digest; only then add a complete
recipe/artifact/catalog/checksum/trust change; and update the owning ABI and
user documentation. State explicitly that adding a catalog row does not create
tool coverage and that a new recipe must still prove the artifact on its target
architecture.

## Affected Components

- `builders/catalog.tsv`: become the minimal source of shared builder-
  architecture identity, platform, and public tag-prefix facts.
- `scripts/builder-catalog.sh`: provide strict shared Bash loading for dispatch
  and publication.
- `build.sh`: replace both literal architecture cases with catalog membership.
- `builders/publish.sh`: derive its safe architecture mapping and tags from the
  catalog while preserving publication behavior.
- `scripts/recipes.py`: load and validate builder architectures instead of
  maintaining a literal set.
- `tests/test_recipes.py`: cover builder-catalog validation, catalog-driven
  dispatch, shared shell lookup, and publisher rejection boundaries.
- `doc/adding-an-architecture.md`: document the end-to-end architecture
  bootstrap and activation procedure.
- `doc/adding-a-binary.md`: define a supported recipe architecture by the
  builder catalog rather than a repeated literal list.
- `doc/architecture/repository/REPOSITORY_MODEL.md`: make builder-catalog
  membership the internal architecture identity authority.
- `doc/architecture/build/BUILD_ENVIRONMENTS.md`: own the catalog fields and
  their relationship to target-specific builder validation.
- `doc/README.md`: link the new task authority from the documentation map.
- `README.md`: make the publisher example architecture-generic and link the
  onboarding procedure without changing current builder/artifact claims.
- `AGENTS.md`: require one valid builder-catalog row for a supported internal
  architecture and remove the stale literal allowlist contract.

## Implementation Sequence

1. Start after the current three architectures have the complete six-tool set
   and stop changing shared catalog, README, trust, and documentation paths.
   Snapshot `./build.sh list`, the three current builder mappings, builder
   locks, and all artifact hashes.
2. Add the exact three-row builder catalog and strict Bash loader. Migrate
   `build.sh` and `builders/publish.sh` without changing their public commands,
   current selections, Docker ordering, or failure boundaries.
3. Replace the Python literal set with builder-catalog loading and conventional
   builder-owner validation. Update fixtures and focused failure cases, then
   prove shell and Python consumers accept and reject the same identities.
4. Add the architecture-onboarding procedure and update only the nearest
   authority and user-entry documents. Keep target ABI tables explicit and
   current rather than treating the three generic catalog fields as complete
   artifact policy.
5. Run focused and root validation, compare the dispatcher list, builder
   mappings, locks, recipe catalog, manifest, and artifact hashes to the
   snapshots, then commit and push only the architecture-contract paths.

## Validation

- Run `bash -n build.sh builders/publish.sh scripts/builder-catalog.sh` and
  `git diff --check`.
- Run the focused unit tests for valid and invalid builder catalogs, including
  exact header, blank/malformed rows, unsafe identifiers/platforms/prefixes,
  ordering, duplicates, missing owners, lock/tag mismatch, and unknown recipe
  and publisher selections.
- Run `python3 scripts/recipes.py validate`,
  `python3 -m unittest tests.test_recipes`, `./build.sh list`, and
  `./validate.sh`.
- Require `./build.sh list` to equal its pre-change output byte for byte and
  verify every current recipe still resolves the same conventional builder and
  artifact paths.
- Exercise the publisher's selection logic without publishing: require each
  real row to resolve the existing directory, platform, versioned prefix, and
  floating tag, and require an unknown or unsafe identifier to fail before any
  Docker or registry call.
- Confirm `recipes/catalog.tsv`, every `builders/*/environment.lock`, every
  builder Dockerfile/package lock/candidate script, `artifacts/SHA256SUMS`, and
  all artifact bytes are unchanged.

## Success Criteria

- One three-field builder catalog is the only machine-readable generic
  allowlist and platform/tag-prefix mapping for architecture dispatch,
  validation, and publication.
- Adding a conforming architecture no longer requires editing `build.sh`,
  `scripts/recipes.py`, or `builders/publish.sh`; it requires one reviewed
  catalog row plus the architecture-owned builder, ABI validation, and docs.
- Existing architecture selections, public tags, builder locks, recipe list,
  artifacts, and publication safety behavior remain exactly unchanged.
- Contributors have one concise procedure that separates builder publication
  from recipe/artifact activation and identifies every required validation and
  trust boundary.
- Architecture-specific ELF, ABI, package, and smoke logic remains explicit;
  no broad rebuild or validation-framework abstraction is introduced.

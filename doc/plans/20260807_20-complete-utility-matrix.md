# Plan: Present and Preserve the Complete Utility Matrix

## Summary

Replace the crowded architecture-summary table with a compact utility matrix:
one row per utility, one version column, and one download column per supported
architecture. Finalize the repository contract that an architecture is called
ready only when it provides every current utility, while retaining the existing
builder-first onboarding path for architectures still under construction.

Execute this plan only after the fresh-clone rebuild documentation plan and all
preceding artifact plans have produced the complete six-tool by four-
architecture catalog.

## Problem

The README repeats long semicolon-separated binary and recipe lists in each
architecture row. It is difficult to scan, duplicates every tool name and
version, and makes missing combinations easier to overlook. Once the planned
work finishes, rebuild support is uniform and no longer needs a second prose
list: every displayed binary is rebuilt with the same
`./build.sh <tool> <architecture>` interface.

The contributor documentation also distinguishes builders from recipes but
does not state the desired public coverage rule. A future builder-only
architecture must remain possible during publication, while a publicly ready
architecture should not silently expose only a subset of the utilities.

## Scope

In scope:

- Replace the README availability table with a six-row utility matrix covering
  GDB 17.2, GDBserver 16.3, lsof 4.99.5, socat 1.8.1.3, strace 6.16, and tcpdump
  4.99.4 across AArch64, ARMv7, x86-64, and x86.
- Put only direct artifact download links in the matrix; document the one
  generic rebuild form once below it instead of repeating recipe links in every
  row.
- Reduce the build example block to `list`, the generic command shape, and one
  real example while retaining the fresh-clone and prerequisite guidance.
- Update the nearest contributor and architecture authorities so a ready
  architecture means complete current-tool coverage, while a builder may exist
  before artifact activation.

Out of scope:

- Generating README Markdown, adding another catalog/status field, or creating
  a second tool registry solely to enforce presentation.
- Changing recipes, builders, artifacts, checksums, TRUST facts, tool versions,
  or feature profiles.
- Adding batch-build orchestration or rebuilding artifacts for a documentation
  change.

## Design

Use this information shape, with each availability cell linking directly to
the committed executable:

```text
Utility | Version | AArch64 | ARMv7 | x86-64 | x86
```

Each tool and version appears once. Do not put recipe links, prose status, or
multiple semicolon-delimited items inside a cell. Immediately below the table,
state that every displayed combination has a committed recipe at the
conventional path and show `./build.sh <tool> <architecture>` plus one valid
copy-paste example. Keep detailed prerequisites and feature tradeoffs in the
existing build section and recipe READMEs.

Define coverage without new machine state: a builder-catalog row may be added
and published before recipes during architecture onboarding, but documentation
must call it a builder-only foundation until every currently distributed tool
has a validated recipe and artifact for that architecture. Likewise, a newly
distributed utility should be planned for every ready architecture. Record
that rule in contributor guidance and the repository model; do not force
generic dispatch or validation to infer rollout status from partial state.

## Affected Components

- `README.md`: replace the crowded availability/rebuild table and repetitive
  build examples with the compact complete matrix and one generic command.
- `AGENTS.md`: state the ready-architecture coverage rule and preserve the
  builder-first exception during onboarding.
- `doc/adding-an-architecture.md`: require complete current-tool coverage before
  presenting a published builder architecture as ready for utility users.
- `doc/adding-a-binary.md`: require a newly adopted utility to cover every
  ready architecture or remain explicitly unactivated planning work.
- `doc/architecture/repository/REPOSITORY_MODEL.md`: distinguish builder
  availability from complete public artifact coverage.

## Implementation Sequence

1. Read the final builder and recipe catalogs plus every source lock; require
   exactly the intended 24 enabled pairs and consistent per-tool versions.
2. Replace the README table and collapse the enumerated build commands without
   removing the prerequisite, trust, source, builder, or onboarding guidance.
3. Add the bounded coverage rule to the four owning contributor/architecture
   documents, preserving builder-first publication.
4. Inspect rendered Markdown and every new relative link, run focused and root
   validation, then commit and push documentation paths only.

## Validation

- Derive the enabled `(tool, architecture)` set from `recipes/catalog.tsv` and
  require it to equal the Cartesian product of the six named tools and four
  supported architectures; require all 24 artifact and recipe README paths to
  exist as regular files.
- Read each `source.lock` and require one consistent displayed version for each
  tool, including both tcpdump and libpcap records where applicable.
- Check every README matrix link resolves inside the repository and inspect the
  rendered table for one short link per architecture cell.
- Run `./build.sh list`, `python3 scripts/recipes.py validate`,
  `git diff --check`, and `./validate.sh`.
- Confirm the diff contains documentation only and all artifact hashes remain
  unchanged.

## Success Criteria

- The README exposes a clean six-by-four download matrix with no missing or
  prose-heavy cells and no duplicated rebuild-support column.
- Every displayed combination has a committed artifact and reproducible recipe
  selected by the same root command.
- Contributor guidance clearly separates a builder-only onboarding state from
  a ready architecture and directs future utilities toward complete ready-
  architecture coverage.
- No builder, recipe, artifact, checksum, trust fact, version, or feature policy
  changes in this documentation-only finalization.

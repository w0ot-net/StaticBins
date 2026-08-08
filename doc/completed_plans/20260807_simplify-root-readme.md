# Plan: Make the Root README a Stable Front Door

*Distilled: 2026-08-08*

## Summary

Replace the exhaustive utility matrix and maintainer runbook in `README.md`
with a small user-facing entry point that remains correct when tools,
architectures, versions, and builder revisions change. Reuse the repository's
existing catalogs, conventional paths, recipe READMEs, trust record, and
documentation map as the detailed authorities; do not introduce another index
or generated document.

## Problem

The root README currently enumerates every tool/version/architecture download,
lists current builder tags, explains authenticated builder publication, tells
maintainers what to run before pushing, and repeats architecture and cache
details. Most of that information already has a machine-readable or
architecture-owned source of truth. Each new binary, architecture, version, or
builder revision therefore forces an unrelated root-document edit and makes the
project's first page harder for ordinary users to scan.

Several stable documents also describe the root README as the public artifact
index or owner of current utility links. Those statements would be false after
the cleanup and would encourage future contributors to rebuild the exhaustive
matrix.

## Scope

In scope:

- Make the root README explain what the project provides, where committed
  binaries are found, how enabled pairs are discovered, how checksums and trust
  records are checked, and how one selected pair is rebuilt.
- Remove per-tool, per-version, per-architecture, and per-builder enumeration
  from the root README.
- Remove builder publication, registry authentication, digest adoption,
  contributor validation, and architecture-onboarding instructions from the
  root README while retaining links to their existing authorities.
- Update the nearest documentation and agent contracts so the catalog and
  repository layout, rather than a hand-maintained README matrix, own current
  artifact discovery.

Out of scope:

- Changing builders, recipes, artifacts, catalogs, checksums, trust facts,
  versions, feature profiles, or ready-architecture coverage rules.
- Adding a generated inventory page, release portal, badge set, documentation
  site, catalog field, or new discovery command.
- Rewriting recipe READMEs or moving maintainer instructions that are already
  present in the builder and contributor authorities.
- Editing completed-plan history; those records remain factual descriptions of
  earlier changes even when the live presentation changes.

## Design

Keep `README.md` as a stable front door with four compact responsibilities:

1. State that the repository distributes ready-to-run static Linux utilities
   with committed rebuild recipes.
2. Link once to `artifacts/` for browsing and to `recipes/catalog.tsv` or
   `./build.sh list` for the current enabled `(tool, architecture)` set. Explain
   the conventional `artifacts/<architecture>/<tool>` path without enumerating
   any current value.
3. Show `sha256sum -c artifacts/SHA256SUMS` and link to `TRUST.md` for assurance
   details.
4. Give one fresh-checkout flow and the generic
   `./build.sh <tool> <architecture>` command. Name only the common build
   boundary at a high level, state that locked public builder images may be
   pulled and non-native builds may use QEMU/binfmt, and route exact
   prerequisites and feature policy to the selected recipe README.

End with a short link to `doc/README.md` for contributor, architecture, and
maintainer documentation. Do not retain the utility matrix, individual recipe
links, a list of example builds, exact builder tags, `docker login`,
`builders/publish.sh`, digest-adoption steps, the AArch64 builder shell command,
or `./validate.sh` contributor guidance. A normal binary or architecture
addition must not require a root README edit unless the generic user workflow
itself changes.

Keep existing owners rather than moving text mechanically. The builder
publication procedure already belongs to
`doc/architecture/build/BUILD_ENVIRONMENTS.md` and
`doc/adding-an-architecture.md`; contribution validation belongs to
`doc/adding-a-binary.md` and `AGENTS.md`; versions, features, and extra host
requirements belong to recipe READMEs; assurance belongs to `TRUST.md`.

Update documentation language that currently calls the README an artifact
index. `recipes/catalog.tsv` is the current enabled-pair authority,
`artifacts/` contains the distributed files, and `artifacts/SHA256SUMS` is the
complete exact file inventory. The complete-coverage rule remains a rollout
contract, but it should refer to the public artifact set rather than a README
index.

## Affected Components

- `README.md`: replace the matrix and maintainer-heavy material with the stable
  discovery, verification, rebuild, and documentation entry points.
- `AGENTS.md`: define the root README's bounded role and replace the public
  artifact-index wording without weakening complete-coverage requirements.
- `doc/README.md`: describe the root README as the concise user entry point,
  not the current artifact index.
- `doc/adding-a-binary.md`: express coordinated rollout in terms of the enabled
  catalog and public artifact set rather than a README-maintained index.
- `doc/adding-an-architecture.md`: remove the requirement to update a
  user-facing artifact index for every activated recipe.
- `doc/architecture/distribution/DISTRIBUTION_MODEL.md`: assign current
  availability and file inventory to the recipe catalog, artifact tree, and
  checksum manifest while keeping the README as a generic entry point.

## Implementation Sequence

1. Snapshot the root links, catalog output, checksum manifest, and artifact
   hashes so the documentation-only change cannot alter distribution state.
2. Rewrite the root README around the four stable responsibilities and remove
   all enumerated or maintainer-only sections.
3. Make the bounded authority-language corrections in the five owning
   documents without expanding their contributor or architecture procedures.
4. Inspect the rendered Markdown and relative links, run focused wording and
   repository validation, then commit and push only the documentation paths.

## Validation

- Run `git diff --check` and inspect the rendered root README for a clear
  discovery, verification, rebuild, and documentation flow.
- Require every relative link in the changed Markdown files to resolve within
  the repository.
- Require `README.md` to contain the generic artifact path,
  `./build.sh list`, `./build.sh <tool> <architecture>`, the checksum command,
  and links to the recipe catalog, trust record, and documentation map.
- Require `README.md` to contain no utility/version/architecture matrix,
  individual artifact or recipe inventory, exact builder tag, `docker login`,
  `builders/publish.sh`, `BUILDER_IMAGE` adoption instruction,
  architecture-specific builder shell command, or pre-push `./validate.sh`
  instruction.
- Search live documentation outside `doc/completed_plans/` and
  `doc/abandoned_plans/` for stale claims that the root README owns the current
  utility links or public artifact index.
- Run `./build.sh list` and `./validate.sh`; require their output and all
  catalog, manifest, artifact, recipe, builder, and trust state to remain
  unchanged.
- Confirm the final diff contains only the six documentation files listed under
  Affected Components.

## Success Criteria

- A user can discover available binaries, verify them, and find the generic
  rebuild command from the root README without reading maintainer operations.
- The root README contains no list whose rows or entries must change when a
  conforming tool, architecture, version, or builder revision is added.
- Detailed versions, features, trust facts, builder publication, and
  contribution procedures remain discoverable through their existing owning
  documents.
- Live documentation consistently treats the recipe catalog, artifact tree,
  and checksum manifest as the current distribution inventory.
- No production code, test code, recipe, builder, artifact, catalog, checksum,
  or trust record changes.

## Execution Notes

Completed on 2026-08-08 in implementation commit
`bba73adcae30d89958097fb93c8c27248ccfa9b6`.

- Replaced the root utility matrix and maintainer runbook with stable artifact
  discovery, checksum and trust verification, one fresh-checkout rebuild flow,
  the conventional output path, and a link to the documentation map.
- Assigned current enabled pairs, distributed files, and their exact inventory
  to `recipes/catalog.tsv`, `artifacts/`, and `artifacts/SHA256SUMS` across
  `AGENTS.md`, the documentation map, both contributor procedures, and the
  distribution architecture authority.
- Made no material deviation from the plan. No builder, recipe, artifact,
  catalog, checksum, trust, production-code, or test-code state changed.
- Validated all 34 relative links in the six changed files, required and
  forbidden README content, removal of stale live artifact-index wording,
  `git diff --check`, and the exact six-file documentation scope.
- `./build.sh list` remained at 24 enabled pairs. `./validate.sh` validated all
  24 recipes and passed 25 tests. All artifact hashes, the checksum manifest,
  and tracked recipe, builder, and trust blobs matched the pre-edit snapshot.

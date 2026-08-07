# Plan: Establish the System Architecture Documentation Tree

*Distilled: 2026-08-07*

## Summary

Create a canonical documentation router and a structured architecture tree that
explains how `static_bins` owns sources, reusable builders, recipes, artifacts,
trust evidence, automation, and distribution. Keep the tree system-oriented:
it will describe stable responsibilities and end-to-end flows without cataloging
each utility or duplicating current artifact status. Preserve the existing
user, trust, contributor, and recipe documents as focused authorities and link
them into the new map.

Execute this plan after `03-expand-reusable-builders.md` is completed or
abandoned because that work changes builder validation and `README.md` facts.
The later per-tool recipe plans do not block this work; the architecture tree
describes the common manufacturing system rather than its current inventory.

## Problem

The repository now has a coherent system but no canonical description of it.
The root dispatcher and catalog select architecture-qualified recipes;
`scripts/recipes.py` validates conventional ownership, tracked source evidence,
builder locks, executable modes, and the artifact manifest; recipe host scripts
run one Buildx path and install validated candidates; separate workflows
validate recipes, publish reusable builders, rebuild qualified artifacts,
publish attestations, and report stable CI results; the repository ruleset
protects `main` history without requiring pull requests or successful checks.

That behavior is discoverable only by reading code, `AGENTS.md`, `TRUST.md`,
`doc/adding-a-binary.md`, recipe READMEs, workflows, and completed plans.
Those documents have valid but different audiences: the root README is a short
user entry point, `TRUST.md` owns current assurance claims and verification
commands, the adding guide is procedural, recipe READMEs are tool-specific, and
completed plans are history. None provides a current authority map or explains
the whole system without mixing mechanism, procedure, live inventory, and
history.

As more architecture-qualified recipes are added, this absence makes it easy to
duplicate rules, mistake historical plans for current design, or change one
stage without recognizing its downstream trust and distribution contracts.

## Scope

In scope:

- Add `doc/README.md` as the canonical documentation router for current
  architecture, user guidance, contributor procedure, tool-local detail, and
  planning history.
- Add a nested `doc/architecture/` tree with one authority for each stable
  system concern and an architecture index that provides the end-to-end map and
  reading order.
- Describe accepted behavior on synchronized `main`, including ownership,
  inputs and outputs, trust boundaries, failure behavior, and the relationships
  among the catalog, recipes, builders, artifacts, workflows, and repository
  ruleset.
- Use system-wide names and path patterns rather than maintaining a second list
  of binaries, versions, hashes, fingerprints, builder tags, or assurance
  statuses.
- Add only the cross-links and concise authority statements needed in the
  existing root, trust, contributor, and agent documents.

Out of scope:

- Adding `DIRECTION.md` or another cross-cutting policy document outside the
  requested router and architecture tree.
- Changing scripts, builders, recipes, workflows, locks, artifacts, catalog
  rows, GitHub settings, validation behavior, or distribution behavior.
- Adding per-binary architecture pages, copying recipe feature matrices, or
  moving live artifact/source status out of `README.md`, `TRUST.md`, or the
  recipe READMEs.
- Documenting unmerged recipe plans, speculative architectures, future
  signature formats, or unsupported build and distribution paths.
- Rewriting completed or abandoned plans, creating architecture decision
  records, adding a documentation generator or linter, or importing the scale
  and migration notebooks of `signals_from_bob_v2`.

## Design

Create this exact initial tree:

```text
doc/
  README.md
  architecture/
    README.md
    repository/
      REPOSITORY_MODEL.md
    build/
      BUILD_PIPELINE.md
      SOURCE_INPUTS.md
      BUILD_ENVIRONMENTS.md
    artifacts/
      ARTIFACT_CONTRACT.md
    trust/
      TRUST_CHAIN.md
      AUTOMATION_AND_GOVERNANCE.md
    distribution/
      DISTRIBUTION_MODEL.md
```

`doc/README.md` is the documentation router, not an architecture essay. It
separates current authorities from procedures and historical records, points
cross-cutting readers to `doc/architecture/README.md`, and makes clear that
`doc/plans/` and `doc/completed_plans/` do not define current behavior.

`doc/architecture/README.md` is the architecture entry point. It defines the
system boundary, presents one compact ASCII flow from official upstream input
through tracked evidence, locked builder, recipe execution, candidate
validation, committed artifact, checksum, and optional attestation, and routes
each concern to the nearest page. It states the document-authority rules:

- `README.md` owns the concise user entry points and current artifact links.
- `TRUST.md` owns current source/artifact assurance status, limitations, and
  verification commands.
- `doc/adding-a-binary.md` owns the contributor procedure.
- `AGENTS.md` owns concise repository guardrails for automated contributors.
- recipe READMEs own versions, features, prerequisites, and tool-specific
  behavior.
- architecture pages own stable system responsibilities and interactions.
- planning directories are implementation records, not current architecture.

Give every lower-level page a short authority statement and keep its content
within these boundaries:

- `repository/REPOSITORY_MODEL.md`: own the directory responsibilities,
  `(name, architecture)` recipe identity, internal architecture identifiers,
  conventional path derivation, three-field catalog role, and the separation
  between generic orchestration and tool-owned policy.
- `build/BUILD_PIPELINE.md`: own the execution sequence from root dispatch to
  recipe host script, Buildx, locked builder, guest build, temporary candidate
  validation, installation, and post-install equality checks. Distinguish this
  ordinary build path from the separate repository validator, explain failure
  scope, and explain why there is no direct-container or classic-Docker
  fallback.
- `build/SOURCE_INPUTS.md`: own tracked archive and `source.lock` roles,
  checksum acceptance, `pgp` versus `checksum-only`, offline verification,
  and the enforcement split: the repository validator authenticates tracked
  inputs while the guest build rechecks committed archive checksums before
  extraction. Cover multi-source recipe ownership and license/input inventory
  boundaries, and link to `TRUST.md` for current fingerprints and status.
- `build/BUILD_ENVIRONMENTS.md`: own architecture builder directories,
  package and environment locks, immutable digests, publish-before-adopt
  lifecycle, internal-to-OCI and native-runner name translations, the public
  `x64-*` builder-tag compatibility spelling, native versus emulated execution,
  and the separation between reusable builder publication and ordinary
  artifact builds.
- `artifacts/ARTIFACT_CONTRACT.md`: own destination architecture semantics,
  static ELF and executable-type checks, stripping, smoke tests, temporary
  candidate replacement and post-install equality rules, `SHA256SUMS`, and the
  distinction between validation, exact rebuilding, and provenance. Explain
  that attested status requires explicit per-artifact qualification after one
  clean native exact rebuild and that a mismatch remains unverified rather than
  being retried.
- `trust/TRUST_CHAIN.md`: own the composed assurance model from upstream
  evidence through locked inputs, builders, recipe validation, exact rebuilds,
  checksums, attestations, and protected history. State what each link proves
  and what the chain does not prove; leave live rows and user commands in
  `TRUST.md`.
- `trust/AUTOMATION_AND_GOVERNANCE.md`: own the three workflow roles, minimal
  permission boundaries, stable `recipe-validation` and
  `artifact-assurance` job names, full-SHA action references, direct-push
  policy, `main` history ruleset, explicit artifact selection, same-job
  rebuild/compare/attest behavior, and the residual repository-owner/GitHub
  trust boundary. Record behavior and stable names, not workflow run IDs or the
  ruleset's numeric ID.
- `distribution/DISTRIBUTION_MODEL.md`: own Git-tracked executables under
  `artifacts/` as the utility distribution surface, GHCR as builder-only,
  the policy against utility images and releases, source-retention rationale,
  checksum manifest role, and license/notice obligations.

Prefer links to existing authoritative tables and commands over copied text.
Use only small ASCII diagrams where they materially clarify ownership or
sequence. Do not add frontmatter, generated navigation, a schema, or a
compatibility layer for nonexistent documentation consumers.

## Affected Components

- `doc/README.md`: add the canonical documentation and authority router.
- `doc/architecture/README.md`: add the system overview, end-to-end flow,
  authority rules, and reading order.
- `doc/architecture/repository/*`: document repository ownership, catalog
  identity, and generic-versus-tool-specific boundaries.
- `doc/architecture/build/*`: document source inputs, builder environments,
  and the supported build pipeline.
- `doc/architecture/artifacts/*`: document the installed artifact and
  validation contract.
- `doc/architecture/trust/*`: document the composed trust chain, automation,
  repository governance, and residual trust.
- `doc/architecture/distribution/*`: document the Git/GHCR distribution
  boundary and license obligations.
- `README.md`: add one concise documentation entry point without expanding
  the artifact or builder sections.
- `TRUST.md`: link the deeper trust architecture while retaining all live
  assurance tables and verification commands.
- `doc/adding-a-binary.md`: link the architecture pages that explain the
  procedure's underlying repository, build, artifact, and trust contracts.
- `AGENTS.md`: identify `doc/README.md` as the authority map and require the
  nearest architecture authority to change when a system contract changes.

## Implementation Sequence

1. Wait for `03-expand-reusable-builders.md` to complete or be abandoned,
   then begin from a clean, synchronized `main`. Re-inventory the current
   dispatcher, validator, builder/recipe scripts, workflows, locks, ruleset,
   and the four existing top-level documentation authorities; do not document
   active-plan behavior as accepted fact.
2. Create `doc/README.md` and `doc/architecture/README.md` first so the
   authority boundaries, reading order, terminology, and end-to-end flow are
   fixed before lower-level pages are written.
3. Write the repository and build pages directly from the current catalog,
   validator, locks, Dockerfiles, and host/guest scripts. Describe invariant
   path patterns and owners rather than enumerating recipe instances.
4. Write the artifact, trust, automation/governance, and distribution pages
   directly from artifact validation, `TRUST.md`, the three workflows, and
   read-only GitHub settings. Keep volatile identities and live status in their
   existing owners.
5. Add the bounded cross-links in `README.md`, `TRUST.md`,
   `doc/adding-a-binary.md`, and `AGENTS.md`; remove no existing operational
   rule or user command.
6. Validate the complete tree, commit it, and push it directly to `main`. Check
   the post-push workflow result selected for the documentation-only change.

## Validation

- Run `git diff --check` and an ASCII scan over every added or changed
  documentation file.
- Resolve every repository-relative Markdown link in `doc/README.md`, the
  architecture tree, and the four updated existing documents; require each
  local target to exist with the intended case.
- Confirm every lower-level architecture page is reachable from both
  `doc/README.md` and `doc/architecture/README.md`, and that reciprocal links
  return readers to the nearest authority rather than creating orphan pages.
- Compare the repository/build pages with `build.sh`,
  `scripts/recipes.py`, `recipes/catalog.tsv`, `builders/*`, and a
  representative recipe host/guest path. Check architecture-name translations,
  the separate validator/build enforcement points, and actual post-install
  semantics. Run `./build.sh list`,
  `python3 scripts/recipes.py validate`, and
  `python3 -m unittest tests.test_recipes`; do not compile an artifact for
  documentation-only changes.
- Compare the trust and automation pages with `TRUST.md`,
  `.github/workflows/*.yml`, the effective repository ruleset, and Actions
  policy using read-only inspection. Require exact stable job names, trigger
  boundaries, and permission boundaries without copying numeric IDs or
  run-specific state.
- Search the new architecture tree for binary/version/hash/fingerprint/status
  inventories, `DIRECTION.md`, utility-image distribution claims, mutable
  builder fallbacks, or descriptions of active plans as current behavior.
- Confirm `README.md` remains concise, `TRUST.md` still owns all live
  assurance rows and verification commands, the adding guide remains
  procedural, recipe READMEs remain tool-specific, and no completed plan was
  changed.
- After the direct documentation-only push to `main`, require
  `artifact-assurance` to pass without an artifact rebuild and confirm the
  path-filtered `recipe-validation` workflow correctly does not run.

## Success Criteria

- A reader can begin at `doc/README.md`, follow the architecture tree, and
  understand the complete source-to-distribution system without reading
  implementation plans or every recipe.
- Every stable system concern has one clearly named architecture authority, and
  each page states its ownership without duplicating volatile inventories from
  existing documents.
- The tree accurately describes the current dispatcher, catalog, validation,
  builder, recipe, artifact, trust, automation, governance, and distribution
  boundaries.
- `README.md`, `TRUST.md`, `doc/adding-a-binary.md`, `AGENTS.md`, recipe
  READMEs, architecture pages, and plan history have explicit non-conflicting
  roles.
- No `DIRECTION.md`, per-binary architecture catalog, generated documentation
  system, production change, external-state mutation, or speculative future
  design is introduced.

## Execution Notes

Completed on 2026-08-07.

- Implementation commit: `a6bfb6d4e205f38f51b72461cf9f7264a068a384`
- Added the documentation router, architecture index, and all eight scoped
  authority pages from the planned tree. Added only bounded authority links to
  `README.md`, `TRUST.md`, `doc/adding-a-binary.md`, and `AGENTS.md`.
- Verified all 14 added or changed Markdown files are ASCII, every local link
  resolves, both indexes reach every topic page, and every topic returns to the
  architecture index. `git diff --check` also passed.
- `./build.sh list`, `python3 scripts/recipes.py validate`, and
  `python3 -m unittest tests.test_recipes` passed; the unit suite ran 20 tests.
- Read-only inspection confirmed the documented workflow roles, stable job
  names, permissions, full-SHA Actions policy, and `main-history` ruleset
  behavior. No scripts, recipes, builders, artifacts, locks, workflows, or
  external settings changed.
- Post-push workflow run `31200067503` passed `artifact-assurance` with both
  rebuild jobs skipped. No `recipe-validation` run was created for the
  documentation-only commit, as required by its path filters.

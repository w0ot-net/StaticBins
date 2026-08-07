# Automation and governance

This page owns workflow roles, permission boundaries, stable checks, and
repository-history controls. Return to the [architecture index](../README.md).

## Workflow roles

- `validate-recipes.yml` performs offline catalog/source/artifact validation,
  focused unit tests, dispatcher listing, and tracked shell syntax. Its stable
  job name is `recipe-validation`. Push execution is path-filtered; pull
  requests and manual dispatch remain available.
- `publish-builder.yml` is a manual maintainer workflow for the architecture
  allowlist. It validates host/target identity, refuses an existing versioned
  tag, and publishes reusable builders with SBOM and provenance. It has
  read-only contents access plus package-write permission and is not an
  ordinary recipe path or a utility publisher.
- `verify-artifacts.yml` runs an explicit, fail-safe selector. Selected pull
  requests rebuild and compare exact bytes without attesting. Selected `main`
  pushes or manual `main` dispatches rebuild, compare, and attest the same file
  in one job. The stable aggregate job name `artifact-assurance` passes only
  when every selected check has the required result; an unrelated change may
  select no expensive build.

Repository Actions default to read permission. Workflows declare narrower or
elevated permissions at workflow/job scope only where needed. Every `uses:`
reference is pinned to a full commit SHA, and repository policy enforces that
invariant.

## History policy

The active `main-history` ruleset targets `main` and blocks deletion and
non-fast-forward updates. Direct fast-forward pushes are allowed; pull requests
and successful checks are not required before a commit reaches `main`.
Accordingly, `recipe-validation` and `artifact-assurance` are important CI
signals rather than merge gates.

The ruleset preserves accepted lineage but does not approve its contents.
Repository write access, settings administration, workflow definitions,
GitHub-hosted runners, registry and attestation services, and GitHub itself
remain explicit trust boundaries. Live assurance claims and verification
commands belong in [`TRUST.md`](../../../TRUST.md), not this architecture page.

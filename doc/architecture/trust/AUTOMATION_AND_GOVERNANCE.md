# Automation and governance

This page owns local automation, workflow permission boundaries, and
repository-history controls. Return to the [architecture index](../README.md).

## Automation roles

- Root `./validate.sh` performs offline catalog/source/artifact validation,
  focused unit tests, dispatcher listing, and tracked shell syntax. Maintainers
  run it directly before committing and pushing. It has no network, Docker, or
  repository-write role.
- `publish-builder.yml` is a manual maintainer workflow for the architecture
  allowlist. It validates host/target identity, refuses an existing versioned
  tag, and publishes reusable builders with SBOM and provenance. It has
  read-only contents access plus package-write permission and is not an
  ordinary recipe path or a utility publisher. It is the only remaining hosted
  workflow and is replaced by a separate implementation plan.

The remaining workflow declares permissions at workflow/job scope and pins
every `uses:` reference to a full commit SHA, as enforced by repository policy.

## History policy

The active `main-history` ruleset targets `main` and blocks deletion and
non-fast-forward updates. Direct fast-forward pushes are allowed; pull requests
and successful checks are not required before a commit reaches `main`.
Accordingly, local validation is a maintainer acceptance step rather than a
merge gate or post-push status.

The ruleset preserves accepted lineage but does not approve its contents.
Repository write access, settings administration, workflow definitions,
the remaining builder workflow and registry, and GitHub itself remain explicit
trust boundaries. Historical artifact attestations remain supplemental
evidence, not the current acceptance mechanism. Live assurance records and
verification commands belong in [`TRUST.md`](../../../TRUST.md), not this
architecture page.

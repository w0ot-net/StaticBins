# Automation and governance

This page owns local automation, external permission boundaries, and repository
history controls. Return to the [architecture index](../README.md).

## Automation roles

- Root `./validate.sh` performs offline catalog/source/artifact validation,
  focused unit tests, dispatcher listing, and tracked shell syntax. Maintainers
  run it directly before committing and pushing. It has no network, Docker, or
  repository-write role.
- `.github/workflows/validate.yml` runs that unchanged command in the
  `repository-validation` job for pushes to `main` and pull requests. The
  Ubuntu 24.04 job has only `contents: read`, checks out without persisting
  credentials, and has no Docker, artifact, attestation, or publication role.
- `builders/publish.sh` is the architecture-allowlisted local maintainer path
  for reusable builders. It refuses an existing versioned tag, runs the
  architecture's candidate validator, and publishes with SBOM and provenance
  through Docker Buildx. It accepts no credentials; a prior external Docker
  login supplies package-write access.

The hosted job is advisory clean-checkout feedback, not a recipe build or
maintainer acceptance boundary. The historical tcpdump signer identity in
`TRUST.md` remains evidence about a different past workflow, not the identity
of this live validation job.

## History policy

The active `main-history` ruleset targets `main` and blocks deletion and
non-fast-forward updates. Direct fast-forward pushes are allowed; pull requests
and successful checks are not required before a commit reaches `main`.
Accordingly, local validation is a maintainer acceptance step rather than a
merge gate. The hosted result is a pull-request or post-push status and is not
required by the ruleset.

The ruleset preserves accepted lineage but does not approve its contents.
Repository write access, settings administration, local maintainer execution,
Docker credentials, the builder registry, and GitHub itself remain explicit
trust boundaries. Historical artifact attestations remain supplemental
evidence, not the current acceptance mechanism. Live assurance records and
verification commands belong in [`TRUST.md`](../../../TRUST.md), not this
architecture page.

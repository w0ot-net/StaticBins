# Plan: Add Minimal Hosted Validation

## Summary

Add one read-only GitHub Actions workflow with exactly two functional steps:
checkout and `./validate.sh`. Run it on pushes to `main` and pull requests while
leaving local acceptance, direct pushes, artifact builds, and publication
unchanged.

## Problem

The fast repository validator runs only on a maintainer's machine, so a pushed
commit has no shared clean-checkout result. A build matrix or new CI framework
is unnecessary; the existing four-second offline command is already the owned
interface.

## Scope

In scope:

- Add one Ubuntu job for pushes to `main` and pull requests.
- Grant only `contents: read`, use a short timeout and SHA-pinned official
  checkout action, then run `./validate.sh` unchanged.
- Document the job as advisory shared feedback, not an acceptance or build
  boundary.

Out of scope:

- Required status checks, ruleset changes, or mandatory pull requests.
- Docker, Buildx, QEMU, builds, caches, artifacts, attestations, or publication.
- Secrets, GHCR permissions, matrices, setup actions, or package installation.

## Design

Create `.github/workflows/validate.yml` with explicit `push` and `pull_request`
triggers, top-level `contents: read`, and one `repository-validation` job on
`ubuntu-24.04` with a five-minute timeout. Pin `actions/checkout` to the reviewed
full SHA of its current major release and identify that release in a comment.
The only run step is `./validate.sh`.

Do not repeat prerequisite checks in YAML: `validate.sh` already checks every
command it needs and produces the actionable error. Do not add dependency
installation or another wrapper. After checkout, the workflow has no intended
network or write role.

Update only the two documents that currently state the live automation and
governance facts. Implement this after the preceding validator/trust plans so
the workflow begins with the final, smaller validation contract.

## Affected Components

- `.github/workflows/validate.yml`: add the two-step read-only job.
- `doc/architecture/trust/AUTOMATION_AND_GOVERNANCE.md`: replace the no-workflow
  statement with the job's exact advisory role and permissions.
- `TRUST.md`: update current governance facts without changing historical
  attestation evidence.

## Implementation Sequence

1. Add the workflow using checkout and the existing validator only.
2. Correct the two current automation/governance records.
3. Push normally and inspect the first run for the exact commit.

## Validation

- Inspect the YAML and confirm it contains one job, two functional steps,
  `contents: read`, no secrets, and no Docker or publication commands.
- Run `./validate.sh` and `git diff --check` locally.
- After pushing, confirm the exact `main` commit passed
  `repository-validation` with `gh run view` or the Actions UI.

## Success Criteria

- Pushes to `main` and pull requests receive one shared validator result.
- The workflow delegates all validation and prerequisite errors to
  `./validate.sh`; it introduces no second validation interface.
- The job is read-only and performs no build, publication, or attestation.
- Local checks and direct-push governance remain unchanged and accurately
  documented.

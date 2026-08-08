# Plan: Add Minimal Hosted Validation

## Summary

Add one read-only GitHub Actions workflow that runs the existing
`./validate.sh` on pushes to `main` and pull requests. Keep local validation as
the pre-push acceptance step and leave the current direct-push ruleset
unchanged. The workflow provides prompt shared feedback without building
artifacts, publishing containers, or handling credentials.

## Problem

Repository validation is fast and comprehensive for committed metadata, but it
runs only on a maintainer's machine. The repository consequently has no shared
status showing that the checked-in catalog, sources, artifacts, tests, shell
syntax, and, after the preceding plans, trust records validate on a clean hosted
checkout. Changing governance to require pull requests or a large build matrix
would be a separate policy decision and is unnecessary for this feedback loop.

## Scope

In scope:

- Add one hosted workflow for pushes to `main` and pull requests.
- Use a single Ubuntu job with read-only repository permissions, a short
  timeout, official checkout, prerequisite checks, and `./validate.sh`.
- Pin third-party action usage by full commit SHA and document its review/update
  expectation.
- Document that the hosted result is advisory and does not replace the required
  local validation or recipe-specific build checks.

Out of scope:

- Changing the `main-history` ruleset, requiring status checks, or requiring
  pull requests.
- Running Docker, Buildx, QEMU compilation, artifact rebuilds, or builder
  publication in Actions.
- Publishing utility images, source releases, attestations, logs, or artifacts.
- Adding secrets, GHCR write permissions, dependency caching, a job matrix, or
  third-party actions beyond official checkout.

## Design

Create `.github/workflows/validate.yml` with `contents: read` as its only
permission and one clearly named `repository-validation` job on the fixed
`ubuntu-24.04` runner label. Give the job a five-minute timeout and use the
current reviewed full commit SHA for `actions/checkout`; retain a comment
naming the action release represented by that SHA. Avoid mutable action tags.

The job should first assert the same external commands that `validate.sh`
requires, including `gpgv`, and then invoke `./validate.sh` from the checkout.
Rely on the runner image only for these basic tools; do not add an unpinned
package-install step or a container image merely to run a four-second offline
validator. A missing prerequisite should fail clearly, making a runner-baseline
change visible and reviewable.

Keep the workflow unprivileged and network-independent after checkout. It does
not use Docker or repository credentials and cannot mutate repository contents
or packages. Update the automation authority and `TRUST.md` governance prose to
distinguish this live advisory check from local maintainer acceptance and from
the historical tcpdump attestation workflow.

Execute this plan after the generic source-record and trust-record plans so the
first hosted contract covers the strengthened final validator and documentation
needs only one transition.

## Affected Components

- `.github/workflows/validate.yml`: define the minimal read-only hosted check.
- `doc/architecture/trust/AUTOMATION_AND_GOVERNANCE.md`: own the live workflow's
  role, permissions, triggers, runner dependency, and non-gating status.
- `TRUST.md`: update repository-governance facts while preserving the limits of
  hosted validation and the historical attestation record.

## Implementation Sequence

1. Complete the two validator plans and verify the final `./validate.sh`
   contract locally.
2. Add the minimal workflow with explicit triggers, permissions, timeout,
   pinned checkout action, prerequisite assertion, and one validation command.
3. Update the automation authority and live trust/governance record to describe
   exactly what the workflow does and does not establish.
4. Validate locally, push under the repository's normal workflow, and inspect
   the first hosted run for the pushed commit.

## Validation

- Inspect the workflow as YAML and confirm it has only `contents: read`, no
  secret references, no write operations, and no Docker or publication steps.
- Run `./validate.sh` and `git diff --check` locally.
- After pushing, use the GitHub Actions UI or `gh run list`/`gh run view` to
  confirm `repository-validation` ran for the exact `main` commit and passed.
- If a pull request event is available later, confirm the same job uses no
  elevated permissions; creating a pull request solely for this check is not
  required.

## Success Criteria

- Every push to `main` and every pull request receives one shared hosted result
  from the existing offline validator.
- The job is read-only, credential-free, bounded to five minutes, and performs
  no artifact build or publication.
- Local validation and narrow recipe/build checks remain the acceptance
  contract, and direct pushes remain allowed.
- Documentation no longer claims that the repository has no hosted workflow
  and does not overstate what the new check proves.

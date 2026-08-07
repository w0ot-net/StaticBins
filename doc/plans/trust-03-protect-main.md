# Plan: Protect the Artifact Trust Path

## Summary

Protect `main` with a small GitHub ruleset so source, recipes, artifacts, and
their attestations cannot bypass the repository's validation and assurance
checks through an ordinary push. Require pull requests and stable checks, block
force pushes and deletion, and require Actions references to be pinned by full
commit SHA. Do not add a mandatory second reviewer, signed-commit migration, or
organization-scale policy to this single-maintainer repository.

Execute this plan after `trust-02-verify-artifacts.md` has published and tested
the final stable check names. Complete it before deleting the retired utility
packages through `utility-images-02-ghcr-cleanup.md`.

## Problem

As observed through the GitHub API on 2026-08-07, `main` has no branch protection
or repository ruleset, the current head commit is unsigned, and repository
Actions settings do not require SHA-pinned action references. The checked-in
workflows currently pin their actions, but that convention can be removed in the
same direct push that changes an artifact or publishing workflow. Build
attestations identify the workflow and commit that handled a file; they are much
less useful if the trust workflow itself can be silently bypassed or replaced.

Absolute protection from a repository owner is impossible because the owner can
change repository settings. The useful, proportionate goal is to prevent
ordinary direct updates, force pushes, and accidental workflow bypass while
leaving an auditable pull-request/check trail.

## Scope

In scope:

- Create one active repository ruleset targeting only `main`.
- Require pull requests and the stable fast-validation and artifact-assurance
  checks before merge.
- Block force pushes and branch deletion.
- Enable repository Actions SHA-pinning enforcement after proving every action
  reference is already a full commit SHA.
- Document the enforced controls, remaining owner/GitHub trust, and how users
  inspect the workflow and attestation identity.
- Record the exact before/after external state and ruleset identifier.

Out of scope:

- Requiring a second human approval while the repository has one active
  maintainer; this can be enabled later when a genuine independent reviewer
  exists.
- Rewriting history to sign old commits, requiring signed commits, adding
  CODEOWNERS solely for self-approval, or creating an organization.
- Self-hosted runners, independent rebuild infrastructure, a custom admission
  controller, or protection from a malicious/compromised repository owner.
- Changing build, source, artifact, checksum, or attestation behavior.
- Vulnerability policy, secret scanning, Dependabot, or unrelated GitHub
  hardening.

## Design

Create one ruleset with a descriptive name such as `artifact-trust-main`, active
enforcement, repository scope, and a branch target that matches only `main`.
Enable the minimum rules:

- require changes through a pull request;
- require the final fast recipe-validation check;
- require the stable `artifact-assurance` gate from
  `.github/workflows/verify-artifacts.yml`;
- block force pushes; and
- block deletion of `main`.

Do not require an approval count greater than zero for now. A pull request still
provides a stable diff, check association, and audit record without pretending
that self-review is independent review. Dismissal, CODEOWNERS, and reviewer-team
rules can be added when another maintainer actually participates.

Use stable gate jobs rather than architecture-specific build job names as
required checks. The fast validation and artifact-assurance gates must report on
every pull request; they may internally skip expensive work when their relevant
paths did not change. This avoids a ruleset that deadlocks documentation-only
changes because a path-filtered required workflow never starts.

Enable `sha_pinning_required` in repository Actions settings only after scanning
every workflow `uses:` entry and confirming a 40-character commit SHA. Keep the
existing `allowed_actions=all` setting: full-SHA enforcement and reviewed
workflow changes address the immediate substitution risk without maintaining a
second allowlist of third-party actions.

Update `TRUST.md` with a short governance section that states exactly what the
ruleset prevents and what it does not. Link to the public ruleset/workflows and
tell users to verify that an artifact attestation names `w0ot-net/static_bins`,
the expected workflow, and a commit reachable from protected `main`. Do not
describe branch protection or an attestation as proof that code is benign.

Treat ruleset creation and Actions-setting mutation as external state. Capture
the initial API responses, create/update only the exact named ruleset, re-read
the effective configuration, and stop on unexpected existing protection rather
than deleting or broadly replacing repository policy.

## Affected Components

- GitHub repository rulesets for `w0ot-net/static_bins`: add one bounded active
  `main` ruleset with required PR/check and ref-integrity controls.
- GitHub repository Actions policy: enable required full-SHA action pinning
  without narrowing the allowed-action set.
- `TRUST.md`: document the protected path, required checks, residual trust, and
  attestation identity inspection.
- `AGENTS.md`: preserve stable gate names, full-SHA action references, and the
  protected-main invariant in future changes.

## Implementation Sequence

1. Confirm both preceding trust plans are complete, the fast validation and
   artifact-assurance gates have passed on `main`, and no relevant workflow run
   or repository-settings change is in flight.
2. Snapshot current branch protection, rulesets, Actions policy, default branch,
   head commit, and exact check names. Scan all `uses:` entries for full commit
   SHAs and fix none here; stop if the prerequisite is not already true.
3. Create the one active `artifact-trust-main` ruleset with no broad branch
   pattern and no unrelated policy. Enable full-SHA Actions enforcement.
4. Open a controlled pull request and prove both required gates report and pass;
   prove a documentation-only pull request does not wait for an absent build
   job.
5. Update and merge the bounded `TRUST.md` and `AGENTS.md` contract through the
   new protected path, then record the ruleset ID and effective API state in the
   completed plan.

## Validation

- Query the GitHub branch/ruleset APIs and require exactly one intended active
  ruleset to target `main`; inspect the returned rules rather than trusting the
  UI summary.
- Prove an ordinary direct push to `main`, a force push, and branch deletion are
  rejected using non-destructive test refs or GitHub's ruleset evaluation where
  direct testing would risk the real branch.
- Open a pull request with no trust-critical changes and require both stable
  gates to report successfully without an expensive build.
- In a test pull request that changes a trust-critical path, require the
  artifact gate to wait for and reflect the native exact-build jobs; do not merge
  intentionally altered artifact bytes.
- Query Actions policy and require `sha_pinning_required=true`; scan every
  workflow and reject tag, branch, or short-SHA `uses:` references.
- Confirm the ruleset does not require a nonexistent reviewer, signed-history
  rewrite, deployment, or unrelated check, and that administrators have no
  accidental broad bypass entry beyond unavoidable repository ownership.
- Verify `TRUST.md` accurately states the repository identity, workflow, required
  checks, and residual owner/upstream/GitHub trust.

## Success Criteria

- Ordinary changes cannot reach `main` without a pull request and successful
  fast-validation and artifact-assurance gates.
- `main` cannot be force-pushed or deleted through the normal repository path,
  and workflow actions must be referenced by full commit SHA.
- Documentation-only pull requests remain cheap and mergeable; trust-critical
  changes receive the source and exact-artifact checks defined by the preceding
  plans.
- Users have a concise, accurate explanation of what repository protection and
  attestations prove and what still requires trust.
- The project gains no fake reviewer ceremony, signed-history migration, custom
  security service, or organization-scale policy.

# Plan: Make Planning Records Explicitly Optional

## Summary

Clarify, prospectively, that a plan document is not a prerequisite for routine
repository work. Keep existing completed plans as historical execution records,
but document that maintainers may implement a bounded conforming change
directly and validate it through the owning repository contracts. This is a
documentation-only policy clarification with no migration or enforcement tool.

## Problem

The repository contains many completed plan documents from its initial build-
out, while `doc/README.md` describes their storage locations without saying
whether future changes are expected to create one. That history can make the
planning ceremony look like a standing repository requirement even though
`AGENTS.md` does not currently require it. Routine changes should be governed
by scope, architecture contracts, validation, and user direction rather than
by the existence of an extra planning file.

## Scope

In scope:

- State that routine, bounded, conforming changes do not require a repository
  plan before implementation.
- Reserve plan documents for explicit user requests or genuinely cross-cutting
  work where a reviewed design and execution sequence add value.
- Describe existing completed plans as historical records, not mandatory
  templates or current architecture authorities.
- Preserve the existing locations for plans that are intentionally created.

Out of scope:

- Deleting, consolidating, rewriting, or reclassifying existing completed or
  abandoned plans.
- Adding plan linting, templates, issue automation, commit-message rules, or a
  numerical threshold for when planning is required.
- Weakening required validation, documentation ownership, rebuild, commit, or
  push rules.
- Changing Codex skills or other tooling outside this repository.

## Design

Add one concise forward-looking rule to `AGENTS.md`: repository plans are
optional for routine work, are required when the user explicitly asks for one,
and are otherwise appropriate only when a cross-cutting or risky change
benefits from review before implementation. Do not attempt to enumerate file or
line-count thresholds; maintainers should judge the coupling and risk of the
outcome, while explicit user direction remains decisive.

Update the implementation-records section of `doc/README.md` to distinguish
active plans, completed historical records, and architecture authorities. Say
plainly that the volume and detail of historical plans reflect prior work and
do not establish a required ceremony for future bounded changes. Preserve the
current plan directories and archive behavior so intentionally planned work
still has an obvious home.

This plan is independent of the three validator/automation plans and may be
implemented or reverted separately.

## Affected Components

- `AGENTS.md`: add the prospective rule governing when repository plan
  documents are and are not required.
- `doc/README.md`: clarify the non-authoritative, historical role of plan
  records and the optional workflow for future work.

## Implementation Sequence

1. Add the concise planning rule to `AGENTS.md` without changing any execution,
   validation, or Git requirements.
2. Align the implementation-records description in `doc/README.md` with that
   rule and keep architecture pages as the stable contract authorities.
3. Cross-check both documents for consistent terminology and no implication
   that existing plans must be migrated.

## Validation

- Run `rg -n "plan|plans|completed_plans|abandoned_plans" AGENTS.md doc/README.md`
  and review every repository-policy statement in context.
- Run `./validate.sh` to confirm the documentation-only change leaves existing
  repository checks intact.
- Run `git diff --check` and inspect the diff for accidental changes to plan
  archives or operational requirements.

## Success Criteria

- Repository guidance clearly allows routine conforming work without creating
  a plan document.
- Explicit user requests for planning and genuinely cross-cutting design work
  still have a documented path under `doc/plans/`.
- Existing completed and abandoned plans remain unchanged and are clearly
  historical rather than normative.
- No validation, build, documentation-authority, commit, or push requirement is
  weakened.

# Plan: Make Planning Records Explicitly Optional

## Summary

Clarify the existing implementation-records paragraph in `doc/README.md` so
routine work does not appear to require a plan document. Edit that owner in
place; do not add policy machinery or duplicate the rule in `AGENTS.md`.

## Problem

`doc/README.md` explains where active and completed plans live but does not say
whether every change needs one. The unusually large historical archive can
therefore look like a standing requirement even though none exists.

## Scope

In scope:

- State that plans are created when explicitly requested or when a maintainer
  chooses design review for cross-cutting work, not for every bounded change.
- Clarify that completed plans are historical records, not templates or current
  authorities.

Out of scope:

- Changes to `AGENTS.md`, validation, Git workflow, or external Codex skills.
- Deleting, reorganizing, or rewriting existing plan archives.
- Templates, linting, automation, thresholds, or new planning rules.

## Design

Replace the current three-sentence implementation-records paragraph in
`doc/README.md` with equally concise text that preserves the current directory
meanings and authority map while making planning optional. This is an edit to
existing text, not a new section or enforcement mechanism.

## Affected Components

- `doc/README.md`: clarify the role of active and historical plan records.

## Validation

- Read the updated implementation-records paragraph with the surrounding
  authority map and confirm it does not alter any operational requirement.
- Run `./validate.sh` and `git diff --check` as required before committing.
- Confirm no plan archive or other policy file changed.

## Success Criteria

- Bounded work is clearly allowed without a repository plan.
- Explicitly requested or intentionally designed plans retain their existing
  locations.
- Historical plans remain unchanged and non-authoritative.
- The implementation is one concise replacement in `doc/README.md` with no new
  tooling or duplicated policy.

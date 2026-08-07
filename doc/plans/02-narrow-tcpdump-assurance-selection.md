# Plan: Narrow tcpdump Assurance Selection

## Summary

Keep tcpdump's exact-rebuild gate sensitive to its own trust boundary while
stopping unrelated catalog and checksum-manifest additions from selecting the
expensive build. Compare tcpdump's records at the base and head revisions and
fail safe to selection whenever that comparison is unavailable or malformed.

## Problem

`.github/workflows/verify-artifacts.yml` currently selects tcpdump whenever any
line in `recipes/catalog.tsv` or `artifacts/SHA256SUMS` changes. Each new tool
plan must add rows to both files, so the current broad path match would rebuild
an unchanged tcpdump once per independently reviewed tool. The repository's
fast validation already checks the full catalog and manifest; exact tcpdump
rebuilds need to track only changes that can alter tcpdump or its asserted
bytes.

## Scope

In scope:

- Retain tcpdump selection for its artifact, recipe, x86-64 builder, the
  assurance workflow, and shared build/validation code that can change its
  output or acceptance.
- When only `recipes/catalog.tsv` is shared, compare the exact
  `tcpdump<TAB>x86_64` row between base and head.
- When only `artifacts/SHA256SUMS` is shared, compare the exact
  `artifacts/x86_64/tcpdump` record between base and head.
- Select tcpdump if either target record changed, disappeared, is duplicated,
  or cannot be read; skip it for unrelated well-formed row additions.

Out of scope:

- Changing recipe dispatch, manifest validation, tcpdump's recipe or artifact,
  assurance status, matrix, runner, or attestation behavior.
- Building a generic dynamic artifact selector or extending exact assurance to
  another artifact.

## Design

Keep selection inside the existing `detect` job rather than adding a script,
schema, or generated matrix. Preserve the direct path cases already owned by
tcpdump. For the two shared files, extract one canonical target record from
`comparison_base` with `git show` and from the checked-out head, require exactly
one match on each side, and compare the complete records. Any command failure,
missing file, zero/multiple target records, or unequal value sets
`tcpdump=true`; only two equal, unique records allow the shared-file change to
remain unselected.

The workflow continues to run `recipe-validation` on every pull request, so
malformed unrelated rows still fail without an exact tcpdump compilation. The
artifact-assurance aggregate check also continues to report on every pull
request and skips its build jobs only when detection safely returns false.

## Affected Components

- `.github/workflows/verify-artifacts.yml`: replace broad shared-file selection
  with fail-safe comparisons of tcpdump's two owned records while preserving
  every direct trust-boundary trigger and required check name.

## Implementation Sequence

1. Isolate the two shared-file cases from the existing direct path matches.
2. Add bounded base/head record extraction with exact uniqueness and failure
   handling; do not introduce a reusable selector abstraction.
3. Exercise positive, negative, malformed, and missing-base cases before
   pushing the workflow-only change.

## Validation

- Parse the changed workflow as YAML, run the embedded Bash through `bash -n`,
  and run `git diff --check`.
- Against synthetic base/head commits, prove unrelated catalog and manifest
  additions return false, while changing/removing/duplicating tcpdump's row or
  checksum and any extraction failure return true.
- Prove each existing direct trigger still returns true, and a documentation-
  only change returns false.
- Let the pull request run one exact tcpdump rebuild because the assurance
  workflow itself changed. After it reproduces the committed checksum, do not
  repeat that compilation locally.

## Success Criteria

- Unrelated valid catalog and checksum records no longer select tcpdump.
- Every tcpdump-specific record change, malformed comparison, and existing
  direct trust-boundary path still selects the exact rebuild.
- Required `recipe-validation` and `artifact-assurance` checks retain their
  names and report on every pull request; no trust claim or artifact changes.

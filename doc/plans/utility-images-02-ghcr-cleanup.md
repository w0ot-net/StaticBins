# Plan: Delete Retired Utility Packages

## Summary

After utility-image publication is removed from `main`, delete the exact public
GDB and tcpdump GHCR packages and their utility cache-scope indexes. Protect the
shared builder package, builder caches, tracked source archives, binaries,
and historical workflow records with explicit allowlists and before/after
checks. This is a separate plan because package deletion is destructive
external state, independently validated, and recoverable only for a limited
window.

This plan depends on `utility-images-01-repository-cleanup.md` being completed
and its validation workflow succeeding.

## Problem

As observed on 2026-08-07, the personal `w0ot-net` package namespace contains
three public container packages linked to `w0ot-net/static_bins`:

- package `14271571`, `static_bins-builder`, which must remain;
- package `14272131`, `static_bins-gdb`, with 22 versions and current tags
  `17.2-aarch64` and `aarch64-latest`; and
- package `14274682`, `static_bins-tcpdump`, with 3 versions and current tags
  `4.99.4-x86_64` and `x86_64-latest`.

The utility publication workflow also created BuildKit cache index keys under
`index-aarch64-gdb-*` and `index-x86_64-tcpdump-*`. Leaving the packages after
the repository stops advertising them is misleading, while deleting by a
broad name pattern or deleting shared BuildKit blobs could damage the reusable
builder environments.

## Scope

In scope:

- Re-resolve and verify the exact GDB and tcpdump package names, IDs, repository
  association, version counts, tags, and tagged digests immediately before
  deletion.
- Prove the repository-cleanup prerequisite is on `main`, its validation run
  succeeded, no utility publisher remains, and no related workflow run is active.
- Delete the complete `static_bins-gdb` and `static_bins-tcpdump` user-scoped
  container packages through GitHub's supported REST endpoint using credentials
  with the required package scopes.
- Delete only Actions cache index entries whose keys begin with the exact
  utility scopes `index-aarch64-gdb-` or `index-x86_64-tcpdump-`.
- Verify both utility packages/tags are gone and the locked AArch64/x86-64
  builder digests still resolve unchanged.
- Record the deletion result and recovery deadline in the completed plan record.

Out of scope:

- Deleting, changing, or republishing `static_bins-builder`, its tags/digests,
  its `index-*-builder-*` caches, or any shared `buildkit-blob-*` cache entry.
- Deleting committed GDB/tcpdump source archives, artifacts, licenses, source
  locks, or recipe content.
- Deleting historical GitHub Actions runs or rewriting completed plans.
- Deleting any unrecognized `static_bins-*` package or cache key discovered at
  execution time; unexpected state is a stop-and-review condition.
- Adding GitHub Release binary assets or another distribution channel.

## Design

Use an exact destructive allowlist containing only `static_bins-gdb` and
`static_bins-tcpdump`. Before mutation, query each through
`/users/w0ot-net/packages/container/<name>`, require that it is public, owned by
`w0ot-net`, and linked to `w0ot-net/static_bins`, and capture its current package
ID plus all tagged versions in a temporary record. Separately capture package
`14271571` and both `BUILDER_IMAGE` values from the committed environment locks.
Do not derive deletion targets from a wildcard or from all packages associated
with the repository.

Delete a user-owned package with the authenticated-user endpoint:

```sh
gh api --method DELETE \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  /user/packages/container/<exact-package-name>
```

Require HTTP 204 for each target. A 401, 403, 404 before deletion, package ID or
owner mismatch, download-limit refusal, or any other unexpected response stops
the operation; do not fall back to a loop that deletes loosely selected version
IDs. GitHub documents that a deleted package may be restored for 30 days if its
namespace has not been reused. Record that deadline, and keep the namespace
unused during the recovery window. If rollback is requested within that window,
use the supported exact-package restore endpoint rather than republishing an
image from repository code.

Actions cache cleanup happens after package deletion and verification. Resolve
the utility index keys again, display the complete ID/key list, and delete each
by exact numeric cache ID. Do not delete `buildkit-blob-*`: those objects share a
BuildKit namespace with builder jobs and will be reclaimed by normal cache
retention when no surviving index references need them.

## Affected Components

- GitHub Packages `static_bins-gdb` and `static_bins-tcpdump`: delete the two
  exact retired utility packages and all versions/attestations they own.
- GitHub Actions caches for `w0ot-net/static_bins`: delete exact GDB/tcpdump
  utility scope index entries only.
- `doc/plans/utility-images-02-ghcr-cleanup.md`: during execution, finalize the
  plan record with resolved IDs/counts, deletion status, verification results,
  and the 30-day recovery deadline; no production file changes are required.

## Implementation Sequence

1. Confirm the repository-cleanup plan is completed on `main`, the worktree is
   clean, its validation run passed, utility publication code is absent, and no
   related Actions run is queued or active.
2. Query all container packages linked to `w0ot-net/static_bins`. Require the
   exact expected set of one protected builder plus the two deletion targets;
   stop for any unknown package rather than expanding scope automatically.
3. Capture package metadata/tagged digests, exact utility cache index IDs/keys,
   protected builder package metadata, and both locked builder digests in a
   narrowly scoped temporary directory.
4. Delete `static_bins-gdb` and `static_bins-tcpdump` individually through the
   authenticated-user REST endpoint, checking the response after each call.
5. Verify both package queries now return 404 and anonymous inspection of all
   four former public tags fails. If only one deletion succeeds, stop and report
   the partial state before any cache cleanup.
6. Reconfirm the builder package and both locked digests resolve, then delete
   only the preflighted utility index cache IDs and verify no matching index key
   remains.
7. Record the final state and recovery deadline, finalize the plan record, and
   commit/push that documentation without adding temporary API output.

## Validation

- Before deletion, use the Packages API to assert exact package names, IDs,
  owner, repository association, visibility, version counts, and tagged digests;
  separately assert the protected builder package identity.
- Search `main` for live workflow/code paths capable of publishing
  `static_bins-gdb` or `static_bins-tcpdump`, and confirm the replacement
  validation workflow has no package-write permission or Docker publication.
- Require a 204 response from each exact delete request, then require package
  GET/list filtering to show only `static_bins-builder` for this repository.
- Anonymously inspect the retired tags and require them to be unavailable.
  Resolve the two exact `BUILDER_IMAGE` digest references from
  `builders/{aarch64,x86_64}/environment.lock` and require both to remain
  available and unchanged.
- List Actions caches after cleanup and require no key beginning
  `index-aarch64-gdb-` or `index-x86_64-tcpdump-`; require all builder index keys
  to remain and do not assert deletion of shared blob entries.
- Verify the tracked source archives and committed GDB/tcpdump artifacts are
  unchanged, the worktree contains no temporary API response, and
  `git diff --check` passes for the finalized plan record.

## Success Criteria

- `static_bins-gdb` and `static_bins-tcpdump` no longer exist as live GHCR
  packages or resolvable tags.
- `static_bins-builder` remains the repository's sole GHCR package and both
  committed builder digest references still resolve exactly.
- No utility cache-scope index remains; no builder index or shared BuildKit blob
  was intentionally deleted.
- Tracked sources, committed binaries, recipes, licenses, historical Actions
  runs, and completed plan records remain intact.
- The completed plan records exact deletion results and the time-bounded package
  restoration window without committing credentials or raw API dumps.

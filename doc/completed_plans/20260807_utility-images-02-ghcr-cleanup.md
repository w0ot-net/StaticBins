# Plan: Delete Retired Utility Packages

*Distilled: 2026-08-07*

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
- Require the active GitHub CLI account to be exactly `w0ot-net` and its classic
  token to have effective `read:packages`, `delete:packages`, and
  `write:packages` access for preflight, deletion, and rollback, plus `repo`
  access for exact Actions-cache deletion.
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
`static_bins-tcpdump`. Before mutation, query `/user` and require login
`w0ot-net`, inspect the token's effective package scopes without printing the
token, require `repo` access for cache cleanup, then query each package through
`/user/packages/container/<name>`. Require that it is public, owned by
`w0ot-net`, and linked to `w0ot-net/static_bins`, and capture its current package
ID plus every version and tagged digest in a mode-`0600` temporary record.
Separately capture package `14271571` and both `BUILDER_IMAGE` values from the
committed environment locks. Do not derive deletion targets from a wildcard or
from all packages associated with the repository.

Delete a user-owned package with the authenticated-user endpoint:

```sh
gh api --include --silent --method DELETE \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  /user/packages/container/<exact-package-name>
```

Redirect each response header to a separate mode-`0600` temporary file and
parse its first status line; require status code 204 in addition to a successful
CLI exit. A 401, 403, 404 before deletion, package ID or owner mismatch,
download-limit refusal, or any other unexpected response stops the operation;
do not fall back to a loop that deletes loosely selected version IDs.

The API does not provide an atomic two-package delete. If the first exact delete
succeeds and the second fails, immediately restore the first through
the same included-header form with method `POST` and endpoint
`/user/packages/container/<exact-package-name>/restore`, require its 204, and
compare its restored owner/repository/version/tag/digest state with the preflight
snapshot before stopping. If restoration itself fails, stop and report the
partial state without touching caches. GitHub documents that a deleted
package may otherwise be restored for 30 days if its namespace has not been
reused. Record that deadline, and keep both namespaces unused during the
recovery window. If a later rollback is requested within that window, use the
same supported exact-package restore endpoint rather than republishing an image
from repository code.

Create a separate empty temporary Docker configuration and use
`DOCKER_CONFIG=<that-directory> docker manifest inspect ...` for all pre/post
utility-tag and locked-builder checks. Never log in through that configuration;
this makes "anonymous" a tested property instead of inheriting the executor's
normal Docker credentials. Treat authenticated package GET/list results as the
authoritative deletion state. After they return 404, retry anonymous manifest
inspection with bounded backoff for at most five minutes to accommodate registry
cache propagation; if a retired tag still resolves, stop before cache deletion
and record the unresolved external state.

Actions cache cleanup happens after package deletion and verification. Resolve
the utility index keys again, display the complete ID/key list, and delete each
by exact numeric cache ID with
`gh cache delete <cache-id> --repo w0ot-net/static_bins`. Do not use a cache key,
prefix, or `--all` as the deletion argument. Do not delete `buildkit-blob-*`:
those objects share a BuildKit namespace with builder jobs and will be reclaimed
by normal cache retention when no surviving index references need them. Record
builder index IDs before and after, but prove protection from the exact deletion
request list rather than assuming GitHub cannot evict a cache independently.

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
   related Actions run is queued or active. Require authenticated GitHub login
   `w0ot-net`, read/delete/write package access for exact rollback, and `repo`
   access for cache deletion.
2. Query all container packages linked to `w0ot-net/static_bins`. Require the
   exact expected set of one protected builder plus the two deletion targets;
   stop for any unknown package rather than expanding scope automatically.
3. Capture package metadata/all versions/tagged digests, exact utility cache
   index IDs/keys, protected builder package metadata, and both locked builder
   digests in a mode-`0700` temporary directory. With an isolated empty Docker
   configuration, anonymously resolve all four utility tags and both locked
   builder digests before deletion.
4. Delete `static_bins-gdb` and `static_bins-tcpdump` individually through the
   authenticated-user REST endpoint, capture headers separately, and require
   status 204 after each call. If the second delete fails, restore and verify the
   first package against the snapshot before stopping; never continue to caches
   from a partial package state.
5. Verify both package queries now return 404 and anonymous inspection of all
   four former public tags fails through the isolated Docker configuration,
   using bounded retries for no more than five minutes before stopping.
6. Reconfirm the builder package and both locked digests resolve, then delete
   only the preflighted utility index cache IDs and verify no matching index key
   remains.
7. Record the final state and recovery deadline, finalize the plan record, and
   commit/push that documentation without adding temporary API output.

## Validation

- Before deletion, use the Packages API to assert exact package names, IDs,
  owner, repository association, visibility, version counts, and tagged digests;
  separately assert the authenticated login, effective scopes, and protected
  builder package identity.
- Search `main` for live workflow/code paths capable of publishing
  `static_bins-gdb` or `static_bins-tcpdump`, and confirm the replacement
  validation workflow has no package-write permission or Docker publication.
- Capture and parse the included response status for each exact delete request
  and require 204, then require package GET/list filtering to show only
  `static_bins-builder` for this repository. Exercise the specified first-delete
  rollback logic if the second request fails rather than accepting partial state.
- With an empty isolated `DOCKER_CONFIG`, anonymously inspect the retired tags
  and require them to be unavailable after a bounded retry window. Resolve the
  two exact `BUILDER_IMAGE` digest references from
  `builders/{aarch64,x86_64}/environment.lock` and require both to remain
  available and unchanged.
- List Actions caches after cleanup and require no key beginning
  `index-aarch64-gdb-` or `index-x86_64-tcpdump-`; confirm every deletion used a
  numeric utility ID and no recorded builder ID. Record any independent builder
  cache eviction without treating it as evidence that the exact deletion
  requests targeted the builder, and do not assert deletion of shared blob
  entries.
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

## Execution Notes

Completed on 2026-08-07 from protected `main` commit
`16865b2d2ced0f7635b99c62165434e7ab8fe9ff`.

- The repository-cleanup prerequisite was present and validation run
  `31157959146` was successful. No utility publisher or active related run
  remained. The authenticated account was exactly `w0ot-net`; the classic token
  advertised `repo`, `write:packages`, and `delete:packages`, while successful
  package GETs proved effective read access. No credential value was recorded.
- The exact preflight package set linked to this repository was protected
  `static_bins-builder` ID `14271571`, GDB ID `14272131`, and tcpdump ID
  `14274682`. GDB had 28 versions; tags `17.2-aarch64` and `aarch64-latest`
  were on version `sha256:bd8cf4c9c7031dbbd7550a865151c82ed7ef0f08c287883ee9ceed33dfeb46b8`.
  Tcpdump had 9 versions; tags `4.99.4-x86_64` and `x86_64-latest` were on
  version `sha256:72d57e5565b5ae9924b54fc602a9cacc35767db1c3fe4256f915cd92c1c2e41d`.
- An isolated, empty Docker configuration anonymously resolved all four utility
  tags and both locked builder digests before deletion. The exact GDB and
  tcpdump package DELETE requests returned HTTP 204 at
  `2026-08-07T08:05:57Z` and `2026-08-07T08:05:58Z`, respectively, so rollback
  was not needed. Authenticated GETs then returned 404 and all four tags were
  anonymously unavailable on the first bounded check.
- Deleted utility cache IDs were `6411210811`, `6411890939`, `6412740440`,
  `6413846671`, `6414147127`, `6415186755`, `6415442851`, `6415573679`,
  `6415585089`, `6417205582`, `6417286210`, `6418407506`, and `6418408240`.
  Every deletion used that numeric ID after its key was rechecked against the
  exact GDB/tcpdump prefixes.
- Protected builder cache IDs `6410131270`, `6411111025`, and `6411803363`
  remained unchanged; no x86-64 builder index was present before deletion. All
  67 shared `buildkit-blob-*` entries remained and were never deletion targets.
- `static_bins-builder` remains the only linked container package. Its locked
  AArch64 digest
  `sha256:23ec20af641f786105254b2c773e2951f66673b9618f350522f60c95e192c5af`
  and x86-64 digest
  `sha256:ed0de561168a27489545d883e790707ae9a34c9412ce6e944c973bc3d848b030`
  both resolved anonymously after cleanup.
- All eight tracked source-evidence files were unchanged. Committed GDB remained
  `5e96e51367020e6be6e2cb0a7f0014573da838a8f7d1d099fd2e5a4a55c820ab`
  and tcpdump remained
  `cdd8f895dceb63d428f137ed910cc083dde2bc76d1006e3468b6f8d654c053b1`.
- The supported 30-day restoration window ends at
  `2026-09-06T08:05:58Z`, provided the deleted namespaces remain unused. A
  requested rollback within that window must use the exact package restore API;
  do not republish either namespace from repository code.

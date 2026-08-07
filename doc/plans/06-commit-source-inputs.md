# Plan: Commit Recipe Source Inputs and Retire Source Releases

## Summary

Make every enabled recipe consume its exact upstream source archives directly
from the tracked recipe directory, with `source.lock` retaining the upstream
provenance and acceptance checksums. Remove the main-repository source-mirror
workflow and release-specific schema, then retire the two existing immutable
source-only releases after the replacement source paths are pushed and
verified. Continue distributing user-facing executables through `artifacts/`;
this plan does not introduce binary GitHub Releases or change GHCR publication.

## Problem

The source-retention implementation currently exposes upstream inputs as
releases of `static_bins`. The GDB and tcpdump source locks name release tags
and `github.com/w0ot-net/static_bins/releases` URLs, normal builds prefer those
URLs, the catalog validator requires their URL shape, and
`.github/workflows/mirror-sources.yml` publishes tool-specific source releases.
The repository currently has two immutable releases with that identity:

- `gdb-17.2-source`
- `tcpdump-4.99.4-libpcap-1.10.4-source`

Those releases solve upstream link availability but make the repository's
release feed look like it publishes GDB, tcpdump, and libpcap releases. They
also add a network source-fetch path and a growing tool-specific workflow even
though the accepted archives are small enough to track with their recipes:
GDB is 24,658,624 bytes, tcpdump is 1,903,612 bytes, and libpcap is 952,153
bytes. A fresh checkout can own and verify these exact 27,514,389 bytes without
another service or release namespace.

The former `05-rebuild-x86-64-tcpdump.md` prerequisite is satisfied by completed
record `doc/completed_plans/20260807_05-rebuild-x86-64-tcpdump.md` and
implementation commit `ddab286`; treat that committed tcpdump recipe and its
documented release inventory as this migration's baseline. Plan
`07-require-buildx.md` is explicitly ordered after this plan because it overlaps
both recipe host scripts and will remove their direct-container branches. Do
not execute plans 06 and 07 concurrently or fold the later backend-policy work
into this source migration.

## Scope

In scope:

- Commit the exact checksum-approved GDB, tcpdump, and libpcap upstream archives
  below the recipes that consume them.
- Make Dockerfile and direct-container builds consume only those tracked source
  bytes and verify the locked checksum before extraction.
- Bring the GDB host path up to the repository's temporary-candidate contract:
  require its validation tools, assert its existing AArch64 `ET_DYN` static-PIE
  shape, and complete its target-architecture smoke test before installation.
- Remove source-release tags and mirror URLs from recipe locks, validation,
  tests, notices, and active documentation while retaining official HTTPS URLs
  as provenance.
- Delete the repository's source-mirror workflow and prohibit future
  source-only releases as part of the recipe contract.
- Rebuild and validate both enabled artifacts after their source-consumption
  path changes.
- After the migration commit is pushed and remotely verified, delete exactly
  the two existing source-only releases and their tags so the repository's
  Releases page is empty.

Out of scope:

- Removing or changing builder and artifact publication through GHCR.
- Creating binary GitHub Releases, artifact checksum sidecars, or a new
  artifact index or directory layout.
- Adding object storage, Git LFS, OCI source artifacts, or a separate source
  mirror repository.
- Mirroring Alpine repositories, making builder bootstrap offline, or vendoring
  every Alpine package source named by a linked-archive inventory.
- Changing GDB, tcpdump, libpcap, Alpine, or dependency versions, configure
  options, feature profiles, or architecture support.
- Migrating the remaining legacy x86-64 artifacts or generalizing arbitrary
  multi-source locks beyond the two real enabled recipes.
- Rewriting completed planning records that factually describe the releases at
  the time those plans were executed.

## Design

Each recipe owns a `sources/` directory inside its existing Docker build
context:

```text
recipes/gdb/aarch64/sources/gdb-17.2.tar.xz
recipes/tcpdump/x86_64/sources/tcpdump-4.99.4.tar.gz
recipes/tcpdump/x86_64/sources/libpcap-1.10.4.tar.gz
```

Keep `SOURCE_ARCHIVE` and, for tcpdump, `LIBPCAP_ARCHIVE` as safe filenames.
The corresponding tracked input is always `sources/<archive>` relative to the
recipe directory, so no new path field or source-store abstraction is needed.
Keep each version, SHA-256, official upstream URL, and license field. Delete
`SOURCE_RELEASE_TAG`, `SOURCE_MIRROR_URL`, and `LIBPCAP_MIRROR_URL`; official
URLs document provenance and maintainer refresh locations but are not normal
build fallbacks.

The catalog validator checks the actual tracked state instead of derived
release metadata. For each supported archive record it requires a regular,
non-symlink file at the derived recipe-local path with Git index mode `100644`,
computes SHA-256, and rejects a missing, untracked, wrongly typed, or mismatched
archive. Retain the existing bounded tcpdump validation for its second libpcap
input rather than introducing a general dependency schema. Reject unexpected
lock fields for both enabled recipes so obsolete mirror fields or unreviewed
extra inputs cannot silently survive.

Dockerfiles copy the recipe's `sources/` directory into the builder stage. The
direct-container branches mount that directory read-only at the same guest
path. Guest scripts copy the selected archive to build scratch space, verify
its locked checksum, and extract only after verification; they no longer
require or invoke `wget` or `curl` to obtain source. A corrupt or missing
tracked archive fails before compilation. Preserve tcpdump's current
candidate-before-install behavior and correct the GDB host path, which currently
installs before its host checks and target smoke test: require `file`, `readelf`,
and `sha256sum`; validate the temporary GDB candidate's AArch64 `ET_DYN`
static-PIE type, absence of an interpreter and `DT_NEEDED`, stripped state, and
version behavior inside the target container; then install and repeat the cheap
host checks. Thus a failed build leaves the previous committed artifact
untouched. The final scratch images continue to contain only the executable and
reviewed distribution materials, not build inputs.

Delete `.github/workflows/mirror-sources.yml` rather than repurposing it. Source
ingest is a reviewed repository change: a maintainer downloads the exact
official archive into temporary storage, verifies its upstream signature when
available and its proposed lock checksum, checks its size against repository
hosting limits, then explicitly stages the archive with the lock and recipe
change. Normal recipe validation continuously rechecks the committed bytes.

Update active notices and documentation to distinguish the roles clearly:
`artifacts/` is the user-facing executable distribution, recipe-local
`sources/` preserves exact upstream inputs, and `source.lock` binds those bytes
to provenance and license metadata. The upstream URL is not an availability
dependency for an ordinary build from a fresh checkout.

The already-published immutable releases are an ordered external-state
migration. First download and verify every release asset needed for the build
against the newly committed archives; the distribution-material archives and
old lock files must be accounted for by tracked repository history and current
license directories. Push the complete source-consumption migration and verify
the three raw files from that exact remote commit. Only then delete releases
`gdb-17.2-source` and `tcpdump-4.99.4-libpcap-1.10.4-source`, delete their tags,
and verify the public release list is empty. Record that GitHub permanently
reserves tag names formerly attached to immutable releases; never attempt to
reuse them. Immediately before deletion, resolve the public releases and tags
again and require the release set, immutable state, asset names, and tag targets
to match the recorded two-release inventory. Stop without deleting anything if
remote state drifted or any unexpected release exists.

## Affected Components

- `recipes/gdb/aarch64/sources/gdb-17.2.tar.xz`: add the exact locked GDB source
  as the recipe's durable build input.
- `recipes/tcpdump/x86_64/sources/{tcpdump-4.99.4.tar.gz,libpcap-1.10.4.tar.gz}`:
  add both exact locked tcpdump recipe inputs.
- `recipes/{gdb/aarch64,tcpdump/x86_64}/source.lock`: remove release/mirror
  identity while retaining filename, version, checksum, upstream provenance,
  and license ownership.
- `recipes/{gdb/aarch64,tcpdump/x86_64}/Dockerfile`: copy tracked source inputs
  into the builder stage without adding them to the final artifact image.
- `recipes/{gdb/aarch64,tcpdump/x86_64}/build.sh`: mount recipe-local source
  directories in the direct-container path, preserve tcpdump's candidate-before-
  install behavior, and move GDB's full host validation ahead of installation
  while explicitly enforcing its existing AArch64 `ET_DYN` static-PIE type.
- `recipes/{gdb/aarch64,tcpdump/x86_64}/build-in-container.sh`: replace mirror
  and upstream downloads with checksum-verified local input consumption.
- `recipes/{gdb/aarch64,tcpdump/x86_64}/licenses/NOTICE.md`: identify the
  tracked archives as the available source copies and remove source-release
  claims.
- `recipes/{gdb/aarch64,tcpdump/x86_64}/README.md`: document source ownership,
  normal-build network boundaries, and the unchanged build commands.
- `scripts/recipes.py`: validate derived local archive paths and bytes, reject
  obsolete or unknown lock state, and stop deriving release URL invariants.
- `tests/test_recipes.py`: materially cover present, missing, corrupt, unsafe,
  untracked, wrong-Git-mode, multi-source, and obsolete-release-field cases for
  local source inputs.
- `.github/workflows/mirror-sources.yml`: remove the main-repository
  source-release publisher.
- `AGENTS.md`: replace the release-mirror rule with the committed-source rule,
  including checksum, provenance, size review, and no-source-release policy.
- `doc/adding-a-binary.md`: make recipe-local verified archives part of the
  onboarding contract and remove immutable mirror instructions.
- `README.md`: state that committed files under `artifacts/` are the user-facing
  distribution and that builds consume recipe-local source archives.
- `artifacts/{aarch64/gdb,x86_64/tcpdump}`: rebuild and retain only validated
  outputs after the source path changes.
- GitHub releases and tags `gdb-17.2-source` and
  `tcpdump-4.99.4-libpcap-1.10.4-source`: delete only after the replacement
  tracked sources are pushed and verified.

## Implementation Sequence

1. Confirm the completed tcpdump plan and commit `ddab286` are present, require
   a clean ownership boundary from plan 07 and unrelated work, and inventory the
   two public immutable releases and all of their assets before changing active
   source references.
2. Download the three official archives to a narrowly scoped temporary
   directory, compare them with the existing release assets, verify the locked
   SHA-256 values, inspect their sizes, and add them under the consuming
   recipes' `sources/` directories.
3. Reduce both source locks to local acceptance metadata plus official
   provenance. Explicitly stage the archives, then update the validator and
   focused tests to require Git-tracked, non-executable regular recipe-local
   archives, hash their actual bytes, and reject the old release fields.
4. Update both Dockerfiles and both host/guest build paths to copy or mount the
   same local inputs and remove normal-build source downloads. Update notices
   and the nearest recipe documentation in the same ownership change. Refactor
   GDB's host checks around the temporary candidate and require its current
   AArch64 `ET_DYN` static-PIE type, stripped state, and target smoke test before
   installing it.
5. Delete the source-mirror workflow and revise `AGENTS.md`, the onboarding
   guide, and the root README to make tracked artifacts and tracked source
   inputs the authoritative repository contract.
6. Run fast validation, then perform one clean build of GDB and tcpdump through
   the root dispatcher. Announce the expected duration before the AArch64 build
   if emulation will make it exceed ten minutes. Revalidate and replace each
   artifact only after its full architecture, static-link, version, inventory,
   and focused smoke checks pass.
7. Commit and push only the migration paths and validated artifacts. Confirm
   container publication succeeds with the enlarged recipe contexts, then
   anonymously fetch all three source archives from the exact pushed commit and
   compare their hashes with the locks.
8. Re-query the release API and tags and stop if the exact immutable releases,
   assets, and tag targets differ from the initial inventory or if any
   unexpected release exists. Otherwise delete exactly the two source-only
   releases and their tags. Confirm the repository release API returns no
   published releases, both old asset URLs no longer resolve, all active code
   and documentation are free of those URLs and tags, and clean-checkout builds
   still use the tracked inputs.
9. Finalize the plan record with the migration commit, artifact hashes, remote
   source verification, container publication result, and irreversible release
   deletion outcome.

## Validation

- Run `python3 -m unittest tests.test_recipes`,
  `python3 scripts/recipes.py validate`, `./build.sh list`, Bash syntax checks
  on host scripts, `sh -n` on guest scripts, workflow YAML parsing for the
  remaining workflows, and `git diff --check`.
- Source each lock in a controlled shell and independently run `sha256sum` on
  `sources/${SOURCE_ARCHIVE}` and, for tcpdump,
  `sources/${LIBPCAP_ARCHIVE}`. Confirm the three hashes are respectively
  `1c036c0d72e4b3d1fb5c94c88632add6f9d76f4d7c4d2ea793c12a9f19a3228c`,
  `0232231bb2f29d6bf2426e70a08a7e0c63a0d59a9b44863b7f5e2357a6e49fea`,
  and `ed19a0383fad72e3ad435fd239d7cd80d64916b87269550159d20e47160ebe5f`.
- Exercise validator fixtures proving a missing archive, symlink, untracked
  archive, non-`100644` Git mode, checksum mismatch, unsafe filename, stale
  mirror field, and incomplete tcpdump pair fail before build or matrix
  emission.
- Search active contracts and implementation paths (`AGENTS.md`, `README.md`,
  `doc/adding-a-binary.md`, `.github/workflows/`, `recipes/`, `scripts/`, and
  `tests/`) for `SOURCE_RELEASE_TAG`, `SOURCE_MIRROR_URL`,
  `LIBPCAP_MIRROR_URL`, the two retired tags, and main-repository source-release
  URLs; require no matches. Historical completed plans are exempt.
- Inspect both guest scripts and controlled build logs to confirm no source
  archive is downloaded and that checksum verification occurs before
  extraction. Confirm Docker builds receive the archives from their existing
  bounded recipe contexts and final scratch images do not contain them.
- Run `./build.sh gdb` and `./build.sh tcpdump`. On each temporary candidate and
  installed artifact, repeat the `file`, `readelf`, stripping, architecture,
  version, linked-archive inventory, and focused functional smoke checks defined
  by its recipe. Specifically assert GDB remains an AArch64 `ET_DYN` static-PIE
  executable and tcpdump remains an x86-64 `ET_EXEC` executable. Inspect the GDB
  command order to confirm every candidate check precedes installation, then run
  a controlled bad-source-checksum failure and prove the committed output hash
  does not change.
- Before deleting external state, download every asset from both immutable
  releases and reconcile it with the three committed archives, current notices,
  locks, or repository history. After pushing, download each raw archive from
  the exact migration commit and verify its checksum anonymously.
- Inspect the catalog-driven GHCR workflow run caused by the pushed recipe
  changes; anonymously pull and smoke-test the unchanged versioned and floating
  image names for both enabled recipes.
- Delete only `gdb-17.2-source` and
  `tcpdump-4.99.4-libpcap-1.10.4-source`, clean up their tags, then query the
  public GitHub releases and tags APIs to confirm both are absent and no other
  external object was changed. Immediately before deletion, prove the public
  release set and both tag targets still equal the recorded inventory; treat any
  drift as a hard stop.
- Confirm unrelated legacy artifacts, builder digests, recipe feature profiles,
  GHCR names, catalog architecture mappings, and pre-existing user work remain
  unchanged.

## Success Criteria

- A fresh checkout contains every upstream utility archive required by the GDB
  and tcpdump recipes, and catalog validation proves each archive matches its
  committed checksum before a build starts.
- Normal GDB and tcpdump builds obtain no source from the network, verify local
  bytes before extraction, retain their one-command interfaces, and produce
  validated artifacts with unchanged versions, ELF types, and intended features.
- Both host paths fully validate a temporary candidate before installation, so
  a source, build, architecture, linkage, stripping, or smoke-test failure leaves
  the previous committed artifact untouched.
- Active locks, implementation, tests, notices, and documentation contain no
  main-repository source-release tags, mirror URLs, or release-shape contract;
  `.github/workflows/mirror-sources.yml` no longer exists.
- `artifacts/` is documented as the user-facing executable distribution, while
  recipe-local `sources/` and locks provide durable rebuild inputs and upstream
  provenance without a second hosting service.
- The public `static_bins` Releases page is empty after both named immutable
  source releases and tags are deliberately retired, with their accepted source
  bytes preserved and independently retrievable from the migration commit.
- GHCR builder and artifact publication, all unrelated artifacts, and historical
  completed-plan records remain unchanged.

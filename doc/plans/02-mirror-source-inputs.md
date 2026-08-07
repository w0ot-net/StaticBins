# Plan: Mirror and Lock GDB Source Inputs

## Summary

Give the GDB recipe one owner for source metadata and a repository-controlled,
immutable mirror of the exact upstream archive. Preserve the official upstream
URL as a checksum-equivalent fallback, distribute the applicable license and
source notices with the binary/image, and keep the user build one command.

This plan assumes `01-lock-build-environment.md` is complete so source fetching
runs inside the already locked builder.

## Problem

GDB's version and checksum are repeated in its Dockerfile and two scripts, and
the only accepted archive location is the GNU server. If that endpoint is
unavailable, a fresh checkout cannot rebuild even though the builder is public.
The repository currently has no release assets, release immutability is
disabled, and the distributed artifact has OCI license metadata but no
committed license/source notice copied into the final image.

## Scope

In scope:

- Add one per-recipe lock for the GDB version, filename, SHA-256, official URL,
  repository mirror URL/tag, and license identifier.
- Enable immutable releases for this repository and publish the verified GDB
  archive as an immutable release asset without allowing replacement.
- Make the GDB guest build try the repository mirror and official endpoint,
  accepting bytes only when they match the single locked checksum.
- Commit and distribute the GDB license plus a factual notice/source inventory
  mapping every static archive in the final link either to the locked GDB source
  or to its exact Alpine package, declared license, license text, and
  authoritative source location.
- Remove duplicate GDB source/version arguments from callers and rebuild the
  committed artifact.

Out of scope:

- Mirroring the whole Alpine repository or every package present in the builder.
- Legal conclusions beyond the factual distribution inventory; an archive or
  package that cannot be mapped to source and license evidence blocks
  publication and is documented rather than guessed.
- Generalizing source downloads across hypothetical tools; each recipe owns its
  lock and fetch logic until a second real consumer justifies a helper.
- The recipe catalog, new binaries, multi-architecture support, and
  byte-for-byte reproducibility.

## Design

Add `aarch64_alpine_build_scripts/gdb/source.lock` as a POSIX-shell-readable
assignment file containing `SOURCE_VERSION`, `SOURCE_ARCHIVE`, `SOURCE_SHA256`,
`SOURCE_UPSTREAM_URL`, `SOURCE_RELEASE_TAG`, `SOURCE_MIRROR_URL`, and
`SOURCE_LICENSE`. The GDB Dockerfile copies this file into the builder stage;
the direct-container branch of the host script mounts it read-only at the same
path. The guest script sources it, downloads each approved URL to a new
temporary path, verifies SHA-256 before extraction, and reports all failures
without ever accepting unchecked bytes. The Dockerfile and host script stop
passing duplicate version/checksum build arguments.

Add `aarch64_alpine_build_scripts/gdb/licenses/` with the upstream GDB license
texts and a concise `NOTICE.md`. Capture the final verbose static link (or linker
map). Map archives built by the GDB tree to `source.lock`; map external archives
to the exact package in the locked builder and record its version,
Alpine-declared license, copied license text, and authoritative source location.
An unmapped archive or missing license/source record is a build-publication
blocker; this is a factual inventory and must not claim a legal conclusion. The
final scratch image can copy this in-context directory to
`/usr/share/licenses/gdb/` while retaining `/gdb` as its entry point.

Add a manually invoked `mirror-sources.yml` workflow with `contents: write`. It
checks out the reviewed commit, reads `source.lock`, verifies repository release
immutability is enabled, creates the release as a draft, downloads and verifies
the official archive, uploads the archive, lock, and reviewed distribution
materials, then publishes once. It fails if the tag/release/assets already
exist. This follows GitHub's
[immutable-release draft/upload/publish model](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases),
which locks the release tag and assets after publication.

The mirror is the first fetch location and GNU remains the second. Both are
availability choices only: `SOURCE_SHA256` is the acceptance authority. The
normal build still needs network access, but it no longer has a single external
source host.

## Affected Components

- `aarch64_alpine_build_scripts/gdb/source.lock`: new single owner for GDB
  source, mirror, hash, version, release tag, and license metadata.
- `aarch64_alpine_build_scripts/gdb/Dockerfile`: copy the source lock and
  committed license materials, remove duplicate source arguments, and include
  notices in the final image.
- `aarch64_alpine_build_scripts/gdb/build-in-container.sh`: read the source lock,
  implement two checksum-locked fetch attempts, and preserve existing build and
  ELF validation.
- `aarch64_alpine_build_scripts/gdb/build.sh`: stop owning or passing duplicate
  GDB version/checksum values, mount `source.lock` for the direct-container path,
  and preserve the same user command.
- `aarch64_alpine_build_scripts/gdb/licenses/*`: in-context upstream GDB license
  texts plus the linked-archive package/license/source inventory.
- `.github/workflows/mirror-sources.yml`: new fail-closed immutable source
  release workflow.
- `.github/workflows/publish-containers.yml`: remove duplicate GDB source build
  arguments and retain the artifact workflow's existing safeguards.
- `aarch64_bins/gdb`: artifact rebuilt from the locked source flow.
- `README.md`: document the source lock/mirror and link the distribution notice.
- `AGENTS.md`: require a source lock, verified mirror, and reviewed distribution
  materials for each newly published recipe.

## Implementation Sequence

1. Create `source.lock` from the currently verified GDB 17.2 archive and refactor
   the Dockerfile/scripts to use it without changing configure/link behavior.
2. Add the in-recipe license directory, capture the final static link, map every
   archive to either locked GDB source or exact package/license/source evidence,
   and fail on an incomplete inventory.
3. Add the source-mirror workflow and its non-replacement preflights; enable
   repository release immutability before running it.
4. Publish the draft source release, verify it is immutable and byte-identical
   to the upstream archive, then make its final URL the first source-lock URL.
5. Rebuild and validate the committed binary and artifact image, then update the
   nearest README and AGENTS contracts.

## Validation

- Run shell syntax checks, parse workflow YAML, validate required source-lock
  fields/URL/tag consistency, and run `git diff --check`.
- Confirm the repository reports release immutability enabled and the source
  workflow refuses an existing release/tag/asset.
- Download the published release asset anonymously and compare its SHA-256 with
  `source.lock` and a fresh official GNU download; verify the release is marked
  immutable.
- Exercise the guest build once with only the mirror reachable and once with
  the mirror forced to fail so the official fallback succeeds; corrupt bytes
  from either endpoint must fail checksum validation.
- Exercise both host branches: the direct-container path must consume the
  mounted lock, and the Buildx/Dockerfile path must consume its copied lock.
- Inspect the final image and in-recipe license directory for the locked
  license/notice materials; reconcile every archive in the captured final link
  with either the GDB source lock or one package/version/license/source entry and
  fail on extras or omissions.
- Run the one-command GDB build, then repeat the AArch64/static-ELF/version and
  focused GDB-remote functional checks.
- Run artifact publication and anonymously pull and execute both GDB tags.

## Success Criteria

- One source lock owns every GDB source/version/hash value consumed by local and
  CI builds.
- Either approved source host can independently supply the exact accepted
  archive, while modified bytes from either host fail closed.
- The repository-controlled archive is attached to an immutable release and is
  byte-identical to the official GDB archive.
- The repository and final image carry GDB license texts and a complete factual
  archive-to-source-or-package/license inventory, with unmapped inputs treated
  as blockers.
- The existing one-command build and published GDB image retain all static and
  functional validation guarantees.

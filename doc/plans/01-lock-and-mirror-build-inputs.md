# Plan: Lock and Mirror Build Inputs

## Summary

Make the existing AArch64 GDB build durable by consuming a builder image by
immutable digest, removing dependency installation from the artifact build, and
mirroring the verified upstream source archive in an immutable repository
release. Keep the current one-command entry point and tool-specific build logic;
the change is limited to making every network-fetched input explicit, auditable,
and fail-closed.

## Problem

`aarch64_alpine_build_scripts/gdb/build.sh` normally pulls a mutable builder tag
and silently falls back to the pinned Alpine base when that pull fails. The
fallback then lets `build-in-container.sh` install whatever package versions are
currently served by the Alpine 3.24 repositories, so local and CI builds need
not use the same dependency closure. GDB's version and checksum are repeated in
three files, and its only source URL is the upstream GNU server. The repository
has no source release, and release immutability is currently disabled.

## Scope

In scope:

- Record the Alpine base, binfmt helper, published builder digest, direct builder
  package versions, and GDB source metadata in committed lock files with one
  owner for each value.
- Make ordinary GDB builds and interactive builder sessions pull the exact
  builder digest; remove the mutable-tag fallback and package installation from
  the artifact build path.
- Retain a separate, explicit maintainer path for building and publishing a new
  builder version, including a documented digest-lock update step.
- Mirror the exact checksum-verified GDB source archive and its source metadata
  in a repository release, then make the recipe try that mirror and the official
  upstream URL while accepting only the locked hash.
- Commit the GDB license/notice next to the distribution metadata and include it
  in both the immutable source release and the final artifact image.
- Enable immutable releases before publishing the source mirror so its tag and
  assets cannot be replaced, and retain GHCR SBOM/provenance publication.
- Rebuild and validate the committed GDB artifact after changing its recipe.

Out of scope:

- Byte-for-byte reproducible output; the existing requirement remains a
  repeatable, validated build.
- A fully offline rebuild of the builder image or a private mirror of the entire
  Alpine package repository.
- Generalizing CI for multiple tools; that is covered by the next ordered plan.
- Adding another binary, migrating the legacy x86-64 artifacts, or adding other
  language toolchains.

## Design

Use committed data files rather than adding a package manager or configuration
service:

- `aarch64_alpine_build_scripts/environment.lock` is a shell-readable assignment
  file containing the base-image digest, binfmt digest, versioned builder tag,
  and exact published builder digest. Host-side scripts source this file. The
  builder Dockerfile receives the locked base through a required build argument
  so it does not maintain a second default.
- `aarch64_alpine_build_scripts/builder-packages.lock` records the direct APK
  package names and installed versions from the locked public builder. The
  builder publication path checks the produced image against this inventory;
  ordinary artifact builds do not invoke `apk` at all.
- `aarch64_alpine_build_scripts/gdb/source.lock` owns the source version,
  filename, SHA-256, SPDX license identifier, immutable release tag/asset URL,
  and official upstream URL. The guest script reads it and tries each approved
  URL into a temporary file, verifying the same checksum before extraction.

The existing `run-builder.sh` and GDB `build.sh` must pull
`ghcr.io/w0ot-net/static_bins-builder@sha256:...` from `environment.lock`.
Failure to retrieve that digest is an actionable error pointing maintainers to
the separate builder publication procedure; it must not silently select a
different dependency environment. This follows GHCR's documented
[pull-by-digest model](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#pulling-container-images-by-digest).
`build-in-container.sh` assumes the locked builder and checks required
commands/libraries before downloading source rather than installing packages.

Split builder lifecycle from artifact lifecycle. A dedicated, manually invoked
builder workflow builds the Dockerfile on native ARM64, validates the package
inventory, and publishes a new versioned tag with SBOM and provenance. It reports
the resulting digest for an explicit lock-file update; artifact publication
uses only the reviewed digest already committed on `main`. Existing tags may
remain for convenience, but recipes never consume them without a digest.

Add a manually invoked source-mirror workflow that reads `source.lock`, creates
a draft release, downloads and verifies the official archive, attaches the
archive plus its lock metadata and applicable notice, and then publishes the
release. It must refuse to replace an existing release or asset. Repository
release immutability is a precondition and is verified before publishing. This
follows GitHub's
[immutable-release draft/upload/publish model](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
and leaves the normal user build dependent only on public GHCR and one of two
checksum-equivalent source endpoints.

## Affected Components

- `aarch64_alpine_build_scripts/environment.lock`: new source of truth for base,
  emulation, builder tag, and builder digest references.
- `aarch64_alpine_build_scripts/builder-packages.lock`: new audited direct-package
  inventory for builder publication.
- `aarch64_alpine_build_scripts/Dockerfile`: consume the required locked base
  argument and the package inventory instead of embedding environment values.
- `aarch64_alpine_build_scripts/run-builder.sh`: consume the exact builder and
  binfmt references from `environment.lock`.
- `aarch64_alpine_build_scripts/build-builder.sh`: new explicit local entry point
  for maintainers to build and inspect a candidate builder without changing the
  ordinary artifact path.
- `aarch64_alpine_build_scripts/gdb/source.lock`: new single owner for GDB source,
  mirror, checksum, version, and license metadata.
- `aarch64_alpine_build_scripts/gdb/Dockerfile`: copy the source lock and require
  the locked builder reference supplied by the caller; include the committed
  license/notice in the final scratch image.
- `aarch64_alpine_build_scripts/gdb/build-in-container.sh`: remove `apk add`, read
  source metadata, fetch from approved endpoints, and verify prerequisites and
  the source hash.
- `aarch64_alpine_build_scripts/gdb/build.sh`: use the shared locks, remove the
  mutable fallback, and preserve output/static-ELF/version validation.
- `aarch64_bins/gdb`: rebuilt artifact produced by the locked recipe.
- `licenses/gdb-17.2/*`: committed upstream license/notice and source-location
  record distributed with the binary and source release.
- `.github/workflows/publish-containers.yml`: stop rebuilding the builder inline
  and build the GDB image from the committed builder digest.
- `.github/workflows/publish-builder.yml`: new native-ARM64 maintainer workflow
  for publishing a reviewed builder candidate and reporting its digest.
- `.github/workflows/mirror-sources.yml`: new fail-closed workflow for creating
  the immutable GDB source release.
- `README.md`: keep the user command concise while documenting immutable inputs,
  the source mirror, and the distinction between normal and maintainer flows.
- `AGENTS.md`: require source locks, digest-pinned builders, and immutable source
  availability for new recipes.

## Implementation Sequence

1. Inspect the currently published builder by digest and record its direct APK
   package versions, base reference, binfmt reference, and GDB source metadata in
   the three lock files. Add syntax/consistency checks before changing callers.
2. Refactor the builder Dockerfile and add `build-builder.sh`; confirm a candidate
   image has the expected architecture, tools, labels, and package inventory.
3. Update `run-builder.sh`, the GDB Dockerfile, and both GDB scripts to consume
   the locks, eliminate runtime package installation, and fail rather than fall
   back to an unlocked environment.
4. Add the builder publication workflow and change artifact publication to use
   only the committed builder digest. Preserve native ARM64 execution, pinned
   action SHAs, GHCR linkage labels, cache, SBOM, and provenance.
5. Enable repository release immutability, add the source-mirror workflow, create
   the immutable GDB 17.2 source release with its license/notice, and verify the
   published assets against `source.lock` before making the mirror the recipe's
   first URL.
6. Perform a clean one-command rebuild, update `aarch64_bins/gdb`, validate the
   artifact and container, then update the nearest documentation.

## Validation

- Run `bash -n` on host/workflow helper scripts, `sh -n` on the guest script,
  parse workflow YAML, and run `git diff --check`.
- Validate that each lock contains one syntactically valid immutable digest and
  that the builder reference has no tag-only fallback.
- Pull the builder with an empty Docker credential directory, inspect its ARM64
  architecture and OCI source label, and compare its direct installed packages
  with `builder-packages.lock`.
- Verify the source release is marked immutable, download its GDB archive
  anonymously, and compare its SHA-256 with `source.lock` and the upstream
  archive. Exercise the recipe with each URL independently.
- From a fresh checkout, run
  `./aarch64_alpine_build_scripts/gdb/build.sh`; confirm the log performs no
  `apk add`, writes `aarch64_bins/gdb`, and reports its size and checksum.
- Use `file` and `readelf` to prove AArch64, no requested interpreter, and no
  `DT_NEEDED` entries; run `gdb --batch --version` and the existing focused
  QEMU GDB-remote breakpoint/variable smoke test.
- Run the artifact publication workflow and anonymously pull and execute both
  the versioned and floating GDB tags.

## Success Criteria

- A normal user command consumes one exact public builder digest and one
  checksum-locked source archive without installing or resolving build packages.
- Retagging the builder or changing a source endpoint cannot change accepted
  build inputs; a missing locked input causes a clear failure.
- The GDB source archive is available from an immutable repository release and
  remains byte-identical to the approved upstream archive.
- Builder updates are an explicit publish-and-lock operation, while ordinary
  GDB builds remain one command.
- The rebuilt committed binary and published GDB image pass architecture,
  static-link, version, and focused debugging checks.

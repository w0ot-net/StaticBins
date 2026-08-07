# Plan: Lock the AArch64 Build Environment

*Distilled: 2026-08-06*

## Summary

Make every ordinary AArch64 GDB build consume one published builder image by
immutable digest. Move package resolution entirely into the separately managed
builder lifecycle, remove the mutable-tag fallback from user builds, and retain
the existing one-command GDB entry point and validation behavior.

## Problem

`aarch64_alpine_build_scripts/gdb/build.sh` pulls a mutable builder tag but
silently falls back to the Alpine base when that pull fails. The guest build
script then runs `apk add`, so a local rebuild can resolve a different package
set from CI even though the base image is pinned. The Alpine, binfmt, and builder
references are also repeated across scripts and Dockerfiles, while the current
publication workflow rebuilds the builder and GDB artifact as one lifecycle.

## Scope

In scope:

- Commit one lock file for the Alpine base digest, binfmt helper digest,
  versioned builder tag, and exact public builder digest.
- Record and enforce exact versions for the builder's direct APK inputs when a
  new builder is created.
- Make GDB builds and interactive builder sessions pull the builder by digest;
  a missing digest must fail with an actionable message instead of falling back.
- Remove `apk add` from the GDB artifact build and verify required builder tools
  and static libraries before compilation.
- Separate explicit builder publication from artifact publication so a builder
  update is published, reviewed, and locked before recipes consume it.
- Rebuild and validate the committed GDB artifact after changing the recipe.

Out of scope:

- GDB source mirroring, source metadata, and distribution notices; those are
  owned by the next ordered plan.
- The recipe catalog and generic CI matrix; those are owned by the third plan.
- A fully offline builder bootstrap or an Alpine repository mirror.
- Byte-for-byte reproducible binaries, new architectures, or new toolchains.

## Design

Add `aarch64_alpine_build_scripts/environment.lock` as a repository-controlled,
shell-readable assignment file. It contains only fixed values for
`ALPINE_IMAGE`, `BINFMT_IMAGE`, `BUILDER_TAG`, and `BUILDER_IMAGE`, where every
image used by a normal build includes `@sha256:...`. Host scripts source this
file; the builder Dockerfile receives `ALPINE_IMAGE` as a required build
argument rather than owning another default. Pulling by digest follows
[GHCR's documented immutable reference model](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#pulling-container-images-by-digest).

Add `builder-packages.lock` containing the direct `name=version` APK
specifications installed by the builder Dockerfile. A small
`build-builder.sh` supplies the locked base, builds only for `linux/arm64`, and
checks the resulting architecture, commands, package versions, and OCI source
label. The published builder digest remains the dependency-closure lock for
ordinary users; rebuilding the builder still requires the pinned Alpine branch
to serve the recorded packages.

`run-builder.sh` and `gdb/build.sh` pull `BUILDER_IMAGE` exactly. A pull failure
stops and points maintainers to `build-builder.sh` and the builder publication
workflow. `gdb/build-in-container.sh` no longer modifies its environment; it
checks required commands and static archives, then performs the existing source
download, configure, link, strip, ELF checks, and version smoke test.

Create a dedicated native-ARM64 `publish-builder.yml` workflow, invoked
manually for a reviewed builder version. It publishes the versioned and floating
tags with OCI metadata, SBOM, provenance, and cache, then reports the resulting
digest. Updating the builder is deliberately two-step: publish the candidate,
then commit that exact digest to `environment.lock`. Until the lock commit,
artifact builds continue using the previous builder. The existing artifact
workflow stops building the builder inline and reads only the committed digest.

## Affected Components

- `aarch64_alpine_build_scripts/environment.lock`: new owner for all base,
  emulation, builder tag, and builder digest references.
- `aarch64_alpine_build_scripts/builder-packages.lock`: new exact direct-package
  inputs for builder creation.
- `aarch64_alpine_build_scripts/Dockerfile`: require the locked base argument and
  install the locked package specifications.
- `aarch64_alpine_build_scripts/build-builder.sh`: new maintainer entry point for
  building and inspecting a candidate ARM64 builder.
- `aarch64_alpine_build_scripts/run-builder.sh`: use the environment lock and
  exact builder digest.
- `aarch64_alpine_build_scripts/gdb/Dockerfile`: require the caller-supplied
  builder digest instead of defaulting to Alpine.
- `aarch64_alpine_build_scripts/gdb/build-in-container.sh`: remove package
  installation and fail on missing builder prerequisites.
- `aarch64_alpine_build_scripts/gdb/build.sh`: consume the shared lock and remove
  the mutable builder/base fallback.
- `.github/workflows/publish-builder.yml`: new manual builder lifecycle with
  native ARM64, pinned actions, cache, SBOM, and provenance.
- `.github/workflows/publish-containers.yml`: consume the committed builder
  digest and stop republishing the builder inline.
- `aarch64_bins/gdb`: artifact rebuilt by the locked environment.
- `README.md`: document the immutable normal path and separate maintainer path.
- `AGENTS.md`: require digest-pinned builders and explicit builder updates.

## Implementation Sequence

1. Inspect the currently public builder and record its exact digest, current
   base/binfmt references, and direct APK versions in the two lock files.
2. Refactor the builder Dockerfile and add `build-builder.sh`; build a candidate
   and verify it matches the recorded direct package inputs and ARM64 contract.
3. Update `run-builder.sh`, the GDB Dockerfile, and both GDB scripts to consume
   the environment lock, eliminate package installation, and fail rather than
   select an unlocked environment.
4. Add the builder workflow and change artifact publication to use only the
   committed digest while retaining native ARM64, pinned actions, OCI linkage,
   cache, SBOM, and provenance.
5. Rebuild `aarch64_bins/gdb` through the normal command, validate it, and make
   the bounded README and AGENTS contract updates.

## Validation

- Run `bash -n` on host/helper scripts, `sh -n` on the guest script, parse both
  workflow files as YAML, and run `git diff --check`.
- Validate that every image in `environment.lock` contains an immutable digest
  and that no ordinary builder reference is tag-only.
- Build a candidate builder and compare its direct installed package versions
  with `builder-packages.lock`; verify ARM64 and the OCI source label.
- Pull the locked builder anonymously with an empty Docker credential directory
  and run `run-builder.sh` command mode to verify its architecture and tools.
- From a clean checkout, run `./aarch64_alpine_build_scripts/gdb/build.sh` and
  confirm no artifact-build step invokes `apk` or falls back to Alpine.
- Validate the output with `file`, `readelf` machine/interpreter/`DT_NEEDED`
  checks, `gdb --batch --version`, and the focused QEMU GDB-remote breakpoint
  and variable smoke test.
- Run both publication workflows as appropriate, then anonymously pull and
  inspect the versioned builder and GDB tags.

## Success Criteria

- Every ordinary GDB build and builder shell uses one exact public builder
  digest, and an unavailable digest fails clearly.
- Artifact builds perform no package installation or dependency resolution.
- Builder changes have an explicit publish-then-lock lifecycle and cannot alter
  recipe inputs before the reviewed digest is committed.
- The rebuilt committed binary and public GDB image pass architecture,
  static-link, version, and focused debugging checks.

## Execution Notes

Implemented the immutable builder lifecycle in commits `5251c9d` and
`37e76fb`. Normal GDB builds and interactive sessions now source
`environment.lock`, pull one exact public builder digest, and stop on failure.
The GDB guest script no longer installs packages; builder creation owns exact
direct APK versions through `builder-packages.lock`. Builder publication is a
separate manual native-ARM workflow, and artifact publication consumes only the
committed digest.

Changed ownership is limited to the AArch64 environment/package locks, builder
and GDB Dockerfiles and wrappers, the two publication workflows, and the
bounded README/AGENTS contracts listed above. The rebuilt
`aarch64_bins/gdb` was byte-identical to the previously committed artifact, so
the binary path required no content commit.

One bounded implementation correction records Alpine's actual `samurai`
package rather than the virtual `ninja` capability; validation still requires
the `ninja` command. The local x86-64 host lacked Docker Buildx, so candidate
image construction and validation ran through the new native-ARM publication
workflow. The public artifact workflow's first source fetch returned transient
`wget` network-failure code 4; an unchanged retry succeeded. Removing that
external source dependency remains Plan 2's explicit scope.

Validation completed successfully:

- Host/guest shell syntax, workflow YAML parsing, digest-shape checks,
  no-fallback/no-`apk` searches, ShellCheck when available, and
  `git diff --check`.
- Exact APK lock resolution against the pinned Alpine ARM64 base.
- Anonymous digest pull plus architecture, installed-package, command, static
  archive, and OCI-source checks for the public builder.
- Manual builder workflow run `31136687335` and artifact workflow run
  `31137059942` (successful unchanged retry).
- `BUILD_JOBS=16 ./aarch64_alpine_build_scripts/gdb/build.sh`, producing GDB
  17.2 with SHA-256
  `5e96e51367020e6be6e2cb0a7f0014573da838a8f7d1d099fd2e5a4a55c820ab`.
- Independent `file`/`readelf` architecture, interpreter, and `DT_NEEDED`
  checks on both the local artifact and the anonymously pulled public image.
- Focused QEMU remote-debugging tests with both payloads: connect, break at
  `main`, step, read `marker = 42`, and observe normal inferior exit.

Deliberately excluded follow-ups remain unchanged: source mirroring and notices
(Plan 2), the generic recipe catalog and CI matrix (Plan 3), offline Alpine
mirroring, byte-for-byte reproducibility, and additional architectures.

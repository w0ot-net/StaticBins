# Plan: Replace the Builder Workflow with Local Publication

## Summary

Add one maintainer command, `./builders/publish.sh <architecture>`, that
validates and publishes a reusable builder to GHCR with Docker Buildx, then
reports its immutable digest for adoption. Remove the builder publication
workflow and update all live instructions and failure messages to use the
local command. This completes the removal of GitHub-hosted execution without
changing any existing builder image, tag, or lock.

## Problem

Builder candidates are already defined and validated by
`builders/<architecture>/build.sh`, but their only documented publication path
is a manual GitHub Actions workflow. The workflow duplicates architecture
selection, lock validation, platform mapping, non-overwrite checks, Buildx
arguments, and digest reporting. Existing recipe failures then send the
maintainer back to that workflow.

That split is unnecessary for the stated maintainer-workstation trust model and
makes every new architecture depend on runner availability. A local publisher
can reuse the existing candidate validators and keep credentials in Docker's
normal external login configuration.

## Scope

In scope:

- Start from the local validation and artifact-trust contract established by
  the preceding plan.
- Add one architecture-allowlisted local publisher for `aarch64`, `armv7`, and
  `x86_64` with the current internal-to-OCI and public-tag mappings.
- Require successful per-architecture candidate validation before a new image
  is pushed.
- Refuse an existing versioned tag, publish the versioned and floating tags
  with Buildx SBOM and provenance output, and report the resulting immutable
  digest.
- Keep registry credentials external to the repository and require the
  maintainer to authenticate with Docker using a GitHub token authorized to
  write packages before publication.
- Delete `.github/workflows/publish-builder.yml` and migrate builder docs,
  trust boundaries, contributor guardrails, and every live workflow-specific
  recovery message, including the now-vacuous Actions-reference pin rule.

Out of scope:

- Publishing a new builder, changing existing tags or digests, modifying
  package locks or Dockerfiles, or adopting a new environment lock. The ARMv7
  r2 builder plan is the first intended real publication.
- Publishing utility images, adding another registry, introducing a release
  service, or storing GHCR tokens in scripts or repository files.
- Generalizing the per-architecture candidate validators or deduplicating
  recipe host scripts beyond their stale recovery text.
- Deleting historical workflow references from completed or abandoned plans.

## Design

Create executable `builders/publish.sh` with one required internal architecture
argument. A direct `case` owns the three small mappings: builder directory,
OCI platform, public floating tag, and required versioned-tag prefix. Do not add
a configuration file or plugin abstraction; these mappings have one consumer
and change only when the repository's architecture allowlist changes.

The publisher requires Docker, Docker daemon access, Docker Buildx, and
Python 3 before registry inspection, emulation, or build work. It loads the
selected `environment.lock`, requires digest-pinned base and binfmt images and
a prefix-conforming `BUILDER_TAG`, and checks the public versioned reference.
Only an explicit registry `manifest unknown`/not-found result permits
publication; authorization, transport, parsing, and other inspection failures
fail closed. An existing versioned tag stops before candidate compilation or
any registry write.

Document `docker login ghcr.io` as a separate maintainer precondition using a
GitHub token with package-write permission. The publisher must neither accept a
token argument nor read or write a repository credential file; Docker's
external credential configuration remains the sole authentication owner.

For a new tag, invoke `builders/<architecture>/build.sh` unchanged so its
package, command, archive, static-link, runtime, ELF, ABI, OCI, and label checks
validate a local candidate. Then run one Buildx push from the same directory
and locked base for the target platform, tagging both the versioned name and
the architecture's existing floating name, with `--sbom=true` and
`--provenance=mode=max`. BuildKit cache may be reused, but classic Docker build
and mutable input fallbacks remain forbidden.

Write Buildx metadata only to a narrowly scoped temporary directory, parse the
reported container-image digest with Python's standard library, require a
valid `sha256:` value, and inspect the published versioned reference for the
expected platform and digest. Print the exact
`BUILDER_IMAGE=ghcr.io/w0ot-net/static_bins-builder@sha256:...` assignment for
the maintainer; never edit `environment.lock` automatically. The separate
adoption step remains a reviewed repository change.

Replace workflow-specific error text in existing recipe host scripts and the
AArch64 interactive runner with the local publisher command. Delete the final
workflow only after the local command and docs are in place.

## Affected Components

- `builders/publish.sh`: add architecture selection, fail-closed tag checks,
  candidate validation, Buildx publication, and digest reporting.
- `.github/workflows/publish-builder.yml`: delete the hosted publication path.
- `AGENTS.md`: define local builder publication and external credential
  handling as the maintainer contract.
- `README.md`: document package-write Docker login, the one local publication
  command, and separate digest adoption without exposing a token.
- `TRUST.md`: remove the remaining live Actions publication dependency while
  leaving the historical tcpdump attestation evidence intact.
- `doc/architecture/build/BUILD_ENVIRONMENTS.md`: replace runner-specific
  publication with the local Buildx lifecycle and QEMU support.
- `doc/architecture/trust/TRUST_CHAIN.md`: replace GitHub Actions builder
  publication with the locally executed Buildx/registry boundary.
- `doc/architecture/trust/AUTOMATION_AND_GOVERNANCE.md`: remove the final
  workflow role and describe local maintainer automation plus protected
  history.
- `builders/aarch64/run.sh`: point locked-builder recovery to
  `builders/publish.sh`.
- `recipes/*/{aarch64,x86_64}/build.sh`: update the bounded set of existing
  locked-builder recovery messages that name the deleted workflow.

## Implementation Sequence

1. Require the preceding local-validation/trust plan to be complete, then add
   the local publisher with the fixed architecture mappings and
   fail-closed preflight/non-overwrite behavior.
2. Update the builder and automation authorities plus root maintainer guidance
   before deleting the workflow.
3. Replace every live recipe/runner recovery reference to
   `publish-builder.yml` with the architecture-specific local command.
4. Delete the publication workflow, run local validation and non-mutating
   refusal checks, then commit and push the planned paths.

## Validation

- Run `bash -n builders/publish.sh` and `./validate.sh`.
- Invoke the publisher with no arguments, too many arguments, and an unknown
  architecture; require an actionable usage error and no Docker or registry
  mutation.
- Invoke each architecture against its already-published current versioned
  tag; require the command to identify the exact reference and refuse before
  candidate compilation or registry writes. Do not publish a test tag.
- Validate the Buildx flags, metadata parsing, platform mappings, fixed GHCR
  repository, package-write external-login instructions, and absence of token
  arguments by focused inspection; the ARMv7 r2 plan will exercise the first
  new-tag push end to end.
- Run syntax checks for every changed shell script, `git diff --check`, and a
  live-file search proving no references to `publish-builder.yml`, hosted
  runners, live GitHub Actions, Actions-reference pin rules, or workflow job
  names remain outside historical plan records and the preserved historical
  tcpdump evidence.
- Confirm `.github/workflows/` has no tracked files and no existing builder,
  artifact, recipe input, checksum, catalog row, tag, or digest changed.

## Success Criteria

- A maintainer has one documented local command for each allowed architecture,
  and it validates before publishing, fails closed on uncertain tag state,
  refuses existing versioned tags, and reports the immutable digest without
  editing locks.
- Builder publication uses Docker Buildx locally with target emulation when
  needed, SBOM/provenance output, and credentials supplied only through normal
  Docker authentication.
- The repository contains no GitHub Actions workflows or live instructions
  that depend on them.
- Existing builder images and environment locks remain unchanged; ARMv7 r2 is
  deliberately deferred to its own executable plan.

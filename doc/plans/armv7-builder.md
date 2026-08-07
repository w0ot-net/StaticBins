# Plan: Add the ARMv7 Little-Endian Builder

## Summary

Add `armv7` as the repository identifier for 32-bit little-endian ARMv7 and
publish one immutable Alpine 3.24.1 reusable builder for OCI platform
`linux/arm/v7`. Reuse the existing architecture-owned builder lifecycle,
Buildx-only host contract, pinned QEMU registration, catalog/dispatcher
allowlists, and GHCR repository. Validate the architecture directly through
OCI metadata, runtime identity, and static C/C++ ELF probes; do not preinstall
tool-specific dependencies or claim utility support until a later tool-owned
recipe adds and validates an ARMv7 artifact.

Execute this plan after `03-expand-reusable-builders.md` is completed or
abandoned so the ARMv7 work can reuse its final validation conventions without
racing the in-progress AArch64 and x86-64 builder changes. Execute it
before `architecture-docs-tree.md` so that plan documents ARMv7 as current
behavior rather than requiring a second architecture-document migration. Do
not execute it concurrently with plans 04-07 when they are changing the shared
README.

## Problem

The repository recognizes only `aarch64` and `x86_64` in its dispatcher,
catalog validator, contributor contract, builder directories, and manual
builder-publication workflow. Consequently, a conforming recipe cannot use
ARMv7 even though Alpine has a maintained `armv7` port and Docker/OCI represent
it as architecture `arm`, variant `v7`, or platform `linux/arm/v7`.

There is no standard GitHub-hosted ARM32 runner: the available Linux runner
architectures are x64 and ARM64. The repository therefore needs one explicit
emulated publication path rather than pretending the ARM64 runner is native
ARMv7 or adding an unavailable runner label. Docker documents QEMU as the
direct way to execute a target platform such as `linux/arm/v7` when no native
node is available.

Relevant platform authorities:

- [Alpine's architecture matrix](https://wiki.alpinelinux.org/wiki/Include%3AArchitecture_support_matrix)
  identifies `armv7` as its 32-bit ARMv7 port.
- [Docker's multi-platform build documentation](https://docs.docker.com/build/building/multi-platform/)
  uses `linux/arm/v7` and documents QEMU/binfmt execution.
- [The OCI image configuration specification](https://github.com/opencontainers/image-spec/blob/main/config.md)
  separates CPU architecture from its optional variant.
- [GitHub's hosted-runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
  lists hosted Linux x64 and ARM64 runners, but no hosted ARM32 runner.

## Scope

In scope:

- Adopt `armv7` as the internal identifier for the Alpine 32-bit,
  little-endian, hard-float ARMv7 port and map it to OCI `linux/arm/v7` only at
  container boundaries.
- Add an architecture-owned `builders/armv7/` with a digest-pinned Alpine base,
  pinned binfmt helper, exact package lock, Buildx candidate command, and the
  minimal compiler/linker and ELF-inspection baseline needed to prove the
  platform.
- Extend the existing manual builder workflow with one ARMv7 case that runs on
  the ARM64 Ubuntu runner, registers `arm` through the committed binfmt digest,
  and publishes a single-platform ARM/v7 builder with SBOM and provenance.
- Publish a non-replaceable `armv7-alpine-3.24.1-r1` tag plus
  `armv7-latest`, inspect the result, and commit its exact public digest before
  repository allowlists accept ARMv7 recipes.
- Extend the root dispatcher, catalog validator, and focused tests to recognize
  `armv7` without adding a catalog row.
- Update the repository, contributor, and agent documentation that owns
  supported architecture and builder facts.

Out of scope:

- Adding or porting GDB, GDBserver, tcpdump, lsof, socat, strace, or any other
  ARMv7 recipe or executable.
- Adding `artifacts/armv7/`, changing `artifacts/SHA256SUMS`, or making an
  ARMv7 artifact-assurance claim in `TRUST.md` before a tool recipe exists.
- Supporting big-endian ARM, ARMv6/Alpine `armhf`, soft-float ABI targets,
  ARMv8 AArch32 tuning, or a generic family of ARM variants.
- Provisioning an ARM32 self-hosted runner, VM, cross-compilation toolchain, or
  Docker Build Cloud; QEMU user-mode execution is sufficient for this builder
  boundary.
- Refactoring the architecture directories into generated files, adding a
  shared platform registry, or generalizing the builder workflow beyond its
  third real case.
- Changing existing AArch64/x86-64 builder tags, digests, packages, artifacts,
  recipes, or publication behavior after plan 03 establishes their baseline.
- Preinstalling GDB, RPC, TLS, packet-capture, or other tool-specific build
  dependencies without an ARMv7 recipe that requires them.
- Modifying the recipe-validation or artifact-assurance workflows solely to
  special-case an architecture with no artifact.

## Design

Use these exact names and boundary translations:

| Concern | ARMv7 value |
| --- | --- |
| Repository directory/catalog identifier | `armv7` |
| Alpine package architecture | `armv7` |
| OCI architecture and variant | `arm` / `v7` |
| Docker/Buildx platform | `linux/arm/v7` |
| Expected container `uname -m` | `armv7l` |
| binfmt registration target | `arm` |
| Versioned/floating builder tags | `armv7-alpine-3.24.1-r1` / `armv7-latest` |
| Publication host | `ubuntu-24.04-arm` (`aarch64`) with pinned QEMU |

Create `builders/armv7/` using the existing builder layout rather than adding a
new abstraction. Its Dockerfile requires `ALPINE_IMAGE`, installs only exact
rows from `packages.lock`, labels the image as the reusable ARMv7 Alpine
toolchain, and performs no package resolution during recipe builds. Start the
package lock with only `build-base` and `file`, provisionally `0.5-r4` and
`5.47-r2`, and re-resolve those exact direct versions against the pinned Alpine
ARMv7 repositories. Require that closure to provide `cc`, `c++`, `make`,
`readelf`, `strip`, static musl, libgcc, and libstdc++; add another direct row
only if an actual baseline probe proves it is missing. Tool-specific recipes
must justify later builder expansion through a new versioned publish-then-lock
change. If the minimal baseline cannot produce and execute both static C and
C++ probes, stop rather than add an unrelated cross-toolchain path.

Pin the ARM/v7 child manifest for Alpine 3.24.1, not the mutable tag or a digest
for another platform. The official manifest currently resolves that child to
`sha256:48bf253520b161ff0f7bd9c6b2aded4126fa8ee2bc29386580b2a8a0322a1742`;
reconfirm its `linux/arm/v7` descriptor before committing it. Reuse the
repository's existing immutable `BINFMT_IMAGE` digest and set the first builder
tag to `armv7-alpine-3.24.1-r1`.

The candidate command follows the other architecture owners: require Docker
and Buildx up front, check ARM/v7 execution, install only the pinned `arm`
binfmt handler when execution is unavailable, recheck execution, then build
and load exactly `linux/arm/v7`. Run package, command, static-archive, and
static C/C++ link probes inside that image. In addition to the common
no-interpreter and no-`DT_NEEDED` checks, require both probes to be ELF32,
little-endian, machine `ARM`, ARM EABI hard-float, and executable under the same
ARM/v7 container. Inspect the loaded image itself as OCI architecture `arm`,
variant `v7`, with
the repository source label. Aggregate validation mismatches as the finalized
plan-03 builders do; do not create an ARMv7 `run.sh` merely for symmetry.

Extend `.github/workflows/publish-builder.yml` with a literal `armv7` choice and
case beside the two existing architectures. Keep `ubuntu-24.04-arm` as the
publication host, but distinguish its expected host machine `aarch64` from the
target platform `linux/arm/v7`. For this case only, validate the locked binfmt
reference, register `arm`, and prove the pinned Alpine image executes before
the existing Buildx publication step. Reuse the same GHCR repository,
versioned-tag non-replacement check, cache, labels, SBOM, and provenance; do not
introduce another workflow or QEMU action.

Bootstrap publication on an implementation branch. Its first pushed commit may
contain the new builder inputs and workflow case with `BUILDER_IMAGE` absent
from the ARMv7 environment lock because no digest exists yet; no catalog row or
allowlist accepts ARMv7 at this point, and this incomplete lock must never reach
`main`. Dispatch the ARMv7 builder from that exact branch, verify the published
image, then add its immutable `BUILDER_IMAGE` digest. Only in that adoption
commit extend the dispatcher and validator allowlists, focused tests, and
documentation, so synchronized `main` never advertises an architecture whose
builder is unavailable.

Adding `armv7` to `build.sh` and `scripts/recipes.py` is sufficient repository
integration. Keep the three-field catalog schema, `(name, architecture)`
identity, derived paths, and existing recipe validation unchanged. Tests should
prove that an otherwise conforming ARMv7 fixture is accepted and dispatched
explicitly, that unsupported spellings such as `arm`, `armhf`, and `armeb`
remain rejected, and that the real catalog/list output is unchanged because
this plan adds no recipe.

The final push changes generic dispatcher/validator paths, so the existing
artifact-assurance selector will conservatively rebuild tcpdump. Do not alter
that trust boundary: require the exact rebuild/attestation job to succeed even
though no distributed artifact is changed. Recipe validation must also pass.

## Affected Components

- `builders/armv7/Dockerfile`: add the pinned-input reusable ARMv7 Alpine
  builder definition.
- `builders/armv7/packages.lock`: record the exact direct ARMv7 packages that
  deliver the minimal static C/C++ and ELF-inspection baseline.
- `builders/armv7/environment.lock`: pin the ARM/v7 Alpine child manifest,
  binfmt helper, non-replaceable tag, and published builder digest.
- `builders/armv7/build.sh`: build and comprehensively validate the local
  ARM/v7 candidate through one Buildx/QEMU path.
- `.github/workflows/publish-builder.yml`: allow and publish the third builder
  platform from an ARM64 hosted runner with pinned ARM emulation.
- `build.sh`: accept `armv7` as an explicit recipe architecture after builder
  adoption.
- `scripts/recipes.py`: accept `armv7` in the catalog architecture allowlist.
- `tests/test_recipes.py`: cover ARMv7 catalog derivation, explicit dispatch,
  and rejection of unsupported ARM spellings.
- `README.md`: list the ARMv7 builder tag and candidate command without adding
  a ready-to-run ARMv7 utility row.
- `doc/adding-a-binary.md`: document `armv7` as a valid recipe architecture and
  its `linux/arm/v7` boundary.
- `AGENTS.md`: add the internal identifier and require explicit ELF
  class/endianness checks for 32-bit ARM artifacts.

## Implementation Sequence

1. Finish or abandon `03-expand-reusable-builders.md`, start from its clean
   synchronized `main` baseline, and schedule this work before
   `architecture-docs-tree.md`. Reuse the finalized builder validation style
   rather than copying the current in-progress worktree or its tool-specific
   package set.
2. Resolve the Alpine 3.24.1 ARM/v7 child manifest and all proposed package
   versions from official repositories. Create the four `builders/armv7/`
   files with no `BUILDER_IMAGE` yet, then run the local candidate command and
   retain its cache until every runtime, package, archive, static-link, ELF,
   endianness, ABI, OCI-platform, and label check passes.
3. Extend the existing builder workflow with the bounded ARMv7 case. Validate
   its syntax and branch inputs, explicitly stage only the builder/workflow
   bootstrap files, commit them on an implementation branch, and push that
   branch without merging the incomplete environment lock to `main`.
4. Dispatch `publish-builder.yml` for `armv7` at that exact branch commit.
   Require the versioned tag to be absent before publication, then inspect the
   reported digest, platform, packages, labels, SBOM, provenance, and runtime
   behavior through an anonymous pull.
5. Add the verified public digest to `builders/armv7/environment.lock`. Extend
   the dispatcher and validator allowlists, focused tests, README, adding
   guide, and agent contract only after the digest is usable.
6. Run the full fast validation and one anonymous digest-pinned ARM/v7 builder
   validation. Confirm the real catalog and artifact tree remain unchanged,
   then commit the adoption paths and push the completed branch directly to
   `main` only if it is a clean fast-forward.
7. Require the resulting `recipe-validation` job and the conservatively
   selected exact tcpdump `artifact-assurance` rebuild/attestation to succeed.
   Correct implementation failures in a new commit; rerun failed jobs for the
   same commit only when the failure is clearly external and transient.

## Validation

- Run `bash -n build.sh builders/armv7/build.sh`, parse the changed workflow as
  YAML, run `git diff --check`, and scan changed text files for non-ASCII bytes.
- Run `python3 scripts/recipes.py validate`,
  `python3 -m unittest tests.test_recipes`, and `./build.sh list`. Require the
  existing two real catalog rows to remain unchanged while focused fixtures
  accept `armv7` and reject `arm`, `armhf`, `armeb`, and unknown identifiers.
- Verify every ARMv7 lock field is a literal safe value, both image references
  contain immutable digests, the Alpine descriptor is exactly
  `linux/arm/v7`, and all direct package versions resolve against that pinned
  base.
- Run `./builders/armv7/build.sh`. Require Buildx-only execution with no mutable
  tag/classic-build fallback, runtime `armv7l`, exact package and command
  inventory, required static archives, and successful execution of every
  static probe.
- For every probe, require `file` plus `readelf` to report ELF32,
  little-endian data, machine `ARM`, the intended ARM EABI hard-float flags,
  executable type, no requested interpreter, and no `DT_NEEDED` entries.
  Inspect the loaded candidate as OCI architecture `arm`, variant `v7`, with
  the expected source label.
- Dispatch the builder workflow once from the bootstrap branch. Confirm it runs
  on `ubuntu-24.04-arm`, observes host `aarch64`, registers only the pinned
  `arm` binfmt handler, builds only `linux/arm/v7`, refuses an existing
  versioned tag, and publishes the versioned and floating tags with SBOM and
  provenance.
- Anonymously pull the published digest and both tags, require them to resolve
  to the same ARM/v7 manifest, rerun the runtime/package/static C/C++ probes, and
  confirm `BUILDER_IMAGE` records that exact digest.
- Confirm `git diff` contains no recipe, catalog, artifact, manifest, trust,
  existing builder, or utility-publication change. After the final main push,
  require `recipe-validation` and `artifact-assurance` to pass, including the
  selected exact tcpdump rebuild.

## Success Criteria

- `armv7` is a documented and tested internal architecture identifier whose
  only container-boundary translation is `linux/arm/v7`.
- GHCR contains one non-replaceable ARMv7 builder tag and floating tag resolving
  to the same immutable OCI `arm`/`v7` image, and the repository lock consumes
  that exact digest with no fallback.
- The builder provides a minimal static C/C++ and ELF-inspection baseline using
  exact Alpine ARMv7 direct packages and fails on missing inputs or any
  architecture, class, endianness, ABI, linkage, runtime, metadata, or
  provenance mismatch.
- A future conforming recipe can use conventional `recipes/<tool>/armv7/` and
  `artifacts/armv7/<tool>` paths without another dispatcher, validator, builder,
  or publication-workflow redesign; tool-specific packages may still require a
  separately versioned builder update.
- Existing recipes, catalog rows, artifacts, checksums, trust claims, builders,
  and distribution behavior remain unchanged, and no ARMv7 utility is claimed
  before a tool-owned recipe supplies one.

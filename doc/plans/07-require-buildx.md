# Plan: Require One Buildx Build Path

## Summary

Make Docker Buildx the single supported container-build backend for local
artifact recipes and reusable-builder candidate commands. Check for Buildx
before any emulation registration, image pull, or compilation, then fail with
an actionable error when it is unavailable instead of selecting a second
orchestration path. Preserve the exact locked images, guest build scripts,
artifact validation, and checksum acceptance rules.

This plan must be executed only after `06-commit-source-inputs.md` is completed
or explicitly abandoned because that plan also changes both recipe host build
scripts and currently describes direct-container source mounts.

## Problem

The GDB and tcpdump host commands prefer `docker buildx build` but, when the
Buildx plugin is absent, directly run `build-in-container.sh` in the locked
builder with a separate set of bind mounts. The reusable-builder commands have
a similar branch: they prefer Buildx but use classic `docker build` on a native
host. These branches retain pinned inputs, but they create two host-side
implementations to maintain and validate. The direct recipe path also bypasses
the Dockerfile that artifact publication uses, so a successful local rebuild
does not prove that the canonical Dockerfile path works.

The alternate paths were useful on development hosts without Buildx, but that
compatibility is not a repository requirement. It conflicts with the smaller
contract that a build either runs through its declared Dockerfile or fails
before doing work.

## Scope

In scope:

- Require a working Docker Buildx plugin in both enabled recipe commands and
  both reusable-builder candidate commands.
- Perform the Buildx prerequisite check before QEMU/binfmt registration, image
  pulls, temporary output creation, or compilation, and report how to satisfy
  the missing prerequisite.
- Remove the recipes' direct locked-builder execution branches and the builder
  commands' native classic-`docker build` branches.
- Keep each existing Dockerfile and guest build script as the canonical build
  path without introducing a backend selector or shared wrapper abstraction.
- Update the nearest repository, recipe, and contributor documentation to name
  Buildx as a prerequisite and prohibit automatic alternate build backends.
- Rebuild and validate both reusable-builder candidates and both enabled
  artifacts through Buildx; replace a committed artifact only if the validated
  output bytes actually change.

Out of scope:

- Changing source ownership or transport; that remains owned by
  `06-commit-source-inputs.md`.
- Removing the checksum-equivalent source-origin fallback if plan 06 is
  abandoned instead of executed; alternate verified source locations are not
  alternate build inputs or backends.
- Changing automatic QEMU/binfmt registration or the target-architecture smoke
  tests.
- Changing builder, Alpine, binfmt, source, dependency, or tool versions and
  digests.
- Adding a `BUILD_BACKEND` option, compatibility shim, shared shell library, or
  general container-build framework.
- Modifying the publication workflows, which already set up and use Buildx as
  their only build backend.
- Claiming or pursuing byte-for-byte reproducibility.

## Design

Treat Buildx as a declared prerequisite rather than a condition that selects
behavior. In each of the four host commands, validate the Docker CLI and the
Buildx plugin before checking the daemon and before any command that can mutate
host binfmt state or pull an image. A missing plugin exits with a concise error
that names Docker Buildx; an unavailable daemon retains its existing distinct
error. Once preflight succeeds, any Buildx build failure propagates immediately
under the existing fail-fast shell settings.

The recipe commands unconditionally run their current `docker buildx build`
invocation with the locked `BUILDER_IMAGE`, target platform, build-job setting,
and local output directory. Delete the alternate `docker run` branch and its
parallel bind-mount/environment wiring. The Dockerfiles continue to copy the
recipe-owned inputs and invoke the existing `build-in-container.sh`, so source,
configure, link, license-inventory, strip, and guest-side validation logic
remain tool-owned and unchanged.

The reusable-builder commands unconditionally run their current Buildx
invocation with the locked Alpine base, target platform, candidate tag, and
`--load`. Delete the host-architecture test and classic `docker build` branch.
Candidate inspection and static-toolchain probes continue against the loaded
image exactly as they do now.

Do not add a new common helper for the small prerequisite check: the four
architecture/tool-owned host commands are the real consumers, and sharing a
shell abstraction would add another interface without removing meaningful
state. Make the policy durable in `AGENTS.md` and the adding-a-binary guide;
focused execution and source inspection are sufficient validation without
teaching the recipe catalog parser to interpret shell implementation details.

The implementation push necessarily matches the `recipes/**` and `builders/**`
path filters in `.github/workflows/publish-containers.yml`. Keep that workflow
unchanged and do not dispatch a parallel run while the automatic run is active.
Require its catalog and artifact-publication jobs to succeed before completing
the plan; a clearly transient external failure may rerun the failed jobs for
the same commit, while an implementation failure requires a corrective commit.

## Affected Components

- `recipes/gdb/aarch64/build.sh`: require Buildx and delete direct execution of
  the GDB guest build inside the builder container.
- `recipes/tcpdump/x86_64/build.sh`: require Buildx and delete the equivalent
  direct tcpdump builder-container path and its duplicate mounts.
- `builders/{aarch64,x86_64}/build.sh`: require Buildx and delete native-host
  classic Docker build selection.
- `README.md`: add Buildx to normal-build and candidate-builder prerequisites.
- `recipes/{gdb/aarch64,tcpdump/x86_64}/README.md`: state that the documented
  one-command recipe requires Buildx.
- `doc/adding-a-binary.md`: require one Dockerfile-driven Buildx path for new
  recipes and disallow automatic alternate build backends.
- `AGENTS.md`: record the fail-fast, single-backend repository invariant.
- `artifacts/{aarch64/gdb,x86_64/tcpdump}`: rebuild through the canonical path,
  revalidate, and update only if the resulting bytes differ.

## Implementation Sequence

1. Complete or abandon `06-commit-source-inputs.md` so its overlapping recipe
   script changes cannot preserve or reintroduce the direct-container branches.
2. Add the early Buildx prerequisite check to all four host commands. Collapse
   each backend conditional to its existing Buildx command and remove only the
   alternate orchestration code.
3. Update the root README, both recipe READMEs, `doc/adding-a-binary.md`, and
   `AGENTS.md` with the Buildx prerequisite and single-backend invariant.
4. Run syntax, catalog, documentation, and controlled missing-Buildx checks.
   Confirm that absence of Buildx exits before binfmt registration, image
   pulls, temporary output creation, or build execution.
5. Build and validate both architecture candidate builders using their direct
   commands. Do not publish a replacement builder or change an environment
   lock because the Dockerfiles and locked inputs are unchanged.
6. Rebuild tcpdump and GDB through the root dispatcher. Before an emulated GDB
   build expected to exceed ten minutes, report the expected work and rough
   duration. Preserve each prior artifact until the recipe's existing
   validation succeeds, then inspect and stage a binary only when its content
   changed.
7. Stage only the plan-owned scripts, documentation, and any validated changed
   artifacts; commit and push them without including unrelated worktree state.
8. Observe the automatically triggered container-publication run for the
   implementation commit and require both enabled matrix entries to succeed.
   Correct implementation failures in code; for a clearly transient external
   failure, rerun the failed jobs for that same commit instead of dispatching a
   separate workflow run.

## Validation

- Run `bash -n` on `recipes/{gdb/aarch64,tcpdump/x86_64}/build.sh` and
  `builders/{aarch64,x86_64}/build.sh`, then run `git diff --check`.
- Run `python3 scripts/recipes.py validate`,
  `python3 -m unittest tests.test_recipes`, and `./build.sh list` to confirm the
  catalog and public dispatcher remain unchanged.
- Search the four host commands and confirm there is no conditional
  `if docker buildx version`, host-architecture `elif`, classic
  `docker build`, or recipe-host reference to `/usr/local/bin/build-static-*`.
  Confirm each command contains exactly one `docker buildx build` invocation.
- Exercise each host command with a controlled Docker CLI whose
  `docker buildx version` fails. Require a nonzero result and the documented
  Buildx error, and verify the command did not attempt `docker info`,
  `docker run`, `docker pull`, `docker build`, or output installation.
- Run `docker buildx version`, then run `./builders/aarch64/build.sh` and
  `./builders/x86_64/build.sh`. Require the existing platform, package,
  command, OCI-label, and static-probe validations to pass for both loaded
  candidate images.
- Run `./build.sh tcpdump` and `./build.sh gdb`. Require each locked builder
  digest pull, Dockerfile build, target-architecture execution, static ELF
  checks, version test, and focused functional test already owned by the
  recipe. Record the final sizes and SHA-256 values and compare them with the
  previously committed artifacts.
- Inspect `.github/workflows/publish-builder.yml` and
  `.github/workflows/publish-containers.yml` to confirm they still set up
  Buildx and have no alternate backend. After the implementation push, verify
  that the automatically triggered `publish-containers.yml` run succeeds for
  both enabled recipe entries for the exact implementation commit.

## Success Criteria

- Every local artifact and reusable-builder candidate command either uses its
  declared Dockerfile through Buildx or exits before performing build setup.
- No host command automatically selects direct guest-script execution or
  classic `docker build` because Buildx is absent.
- Missing Buildx, unavailable Docker, image-pull failure, compilation failure,
  or validation failure each produces a nonzero result without selecting a
  second build path.
- Builder images and all source, environment, dependency, architecture,
  static-link, license, and smoke-test invariants remain unchanged.
- Both builder candidates and both enabled artifacts pass their existing
  validations through the single Buildx path, and active documentation names
  Buildx as a prerequisite.
- The implementation commit's automatic artifact-publication run succeeds for
  both enabled recipes without workflow changes or a separate workflow
  dispatch.

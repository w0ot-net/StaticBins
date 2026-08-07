# Plan: Clarify the Fresh-Clone Rebuild Path

## Summary

Make the committed user documentation provide one accurate, copy-paste path
from a fresh clone to a validated artifact build. Keep the existing recipe
command as the only prerequisite and build authority, and explain how the
public, digest-pinned GHCR builders reduce cold-start work while preserving the
repository's fail-closed environment lock. Correct the one current recipe
README whose abbreviated command no longer selects a unique catalog row.

## Problem

The repository already has the important mechanics: the root dispatcher lists
and selects recipes, every recipe checks its exact host prerequisites before
installing output, reviewed source archives are tracked, and normal builds pull
pre-provisioned builder environments by immutable digest. The root README,
however, begins after cloning and names only Bash, Docker, and Buildx. A new
user must infer the common host tools, whether Docker login is needed, what the
first build downloads, why a later build is faster, and when foreign-target
execution may need privileged `binfmt_misc` registration or full-system QEMU.

The source-input wording can also be read too broadly: ordinary builds do not
need the upstream source URL, but a cold build still contacts public container
registries for the locked runtime probe, binfmt helper when needed, and GHCR
builder. AArch64 GDBserver and strace additionally download their pinned smoke-
test kernel on first use. Finally,
`recipes/tcpdump/x86_64/README.md` still advertises `./build.sh tcpdump` and the
same abbreviated `BUILD_JOBS` example even though the ARMv7 catalog row makes
both commands ambiguous; the root dispatcher correctly rejects them.

## Scope

In scope:

- Add a concise fresh-clone quickstart to `README.md`: clone, enter the
  checkout, state the common host boundary, list recipes, and run one explicit
  `(tool, architecture)` build command.
- Name the common host commands enforced by ordinary recipes and route users
  to the recipe README for tool-specific additions such as full-system AArch64
  smoke-test utilities.
- Clearly separate ordinary anonymous consumption of public, immutable GHCR
  builders from the authenticated maintainer-only builder publication flow.
- Explain cold versus warm behavior without promising a fixed duration:
  tracked source inputs avoid upstream source downloads; cold builds pull
  locked images and may register emulation; Docker and BuildKit retain reusable
  content; emulated compilation may take more than ten minutes.
- State the remaining first-use AArch64 smoke-kernel download and the fact that
  image pulls still make registry/network availability part of the ordinary
  build boundary.
- Correct both ambiguous x86-64 tcpdump dispatcher examples to include
  `x86_64`.

Out of scope:

- Adding a `doctor`, `prepare`, or prerequisite metadata system. The selected
  recipe already checks actual requirements in the required failure order;
  duplicating those lists would create derived state that can drift.
- Adding `build all` or architecture-wide batch builds. They are independently
  implementable, can be expensive under emulation, and are not required to
  rebuild any selected artifact.
- Refactoring duplicated recipe host scripts or changing their prerequisite,
  image-pull, emulation, build, smoke-test, or installation behavior.
- Changing architecture documentation. The existing build-pipeline authority
  already owns image pulls, conditional emulation, external cache retention,
  full-system validation, and fail-closed builder availability.
- Making builds registry-independent, adding mutable or locally rebuilt
  builder fallbacks, or changing GHCR's builder-only distribution role.
- Reducing repository size through LFS, shallow-clone guidance, shared source
  paths, or removal of tracked sources or artifacts.
- Claiming fixed build times, byte-for-byte reproducibility, new attestations,
  or stronger source authentication.

## Design

Keep `README.md` task-oriented. Its build section should begin with a short
fresh-clone sequence using the public repository URL, `cd static_bins`,
`./build.sh list`, and one real explicit command such as
`./build.sh lsof x86_64`. Follow it with a compact prerequisite boundary:
Bash; a usable Docker daemon; Docker Buildx; and the host `file`, `readelf`, and
`sha256sum` commands. Do not add separate manual preflight commands: the
selected recipe remains the executable authority that checks Buildx, Docker,
and its exact host commands before image pulls or compilation. State that
recipe READMEs remain authoritative for additional tools and feature tradeoffs.

Describe GHCR as both a speed and repeatability mechanism. An ordinary build
anonymously pulls the exact builder digest from the selected architecture's
`environment.lock`; it does not resolve Alpine packages or compile a toolchain
from scratch, and it does not need the publication credentials documented for
maintainers. Do not call the complete artifact build offline: the source bytes
and their authentication evidence are local, while the locked public images
must be available and the two full-system AArch64 recipes may fetch their
separately pinned kernel. Explain that cached Docker image content, the external
kernel cache, and BuildKit layers accelerate later runs, while the scripts
retain the exact-digest pull and validation boundary.

Keep host-wide consequences visible before the example build: a non-native
target may cause the recipe to run the pinned binfmt helper with `--privileged`
when target containers cannot already execute. Do not add a generic install
command for Docker, QEMU, or distro packages; those package names and setup
steps vary by host, and the actual recipe checks command availability directly.
Do not publish measured repository or image sizes as stable guarantees. Link
to the existing build-pipeline and build-environment authorities for stable
detail rather than restating or changing their contracts.

In `recipes/tcpdump/x86_64/README.md`, change only the two dispatcher examples
to `./build.sh tcpdump x86_64` and
`BUILD_JOBS=4 ./build.sh tcpdump x86_64`. Retain the direct recipe command,
source, feature, validation, and trust text unchanged.

## Affected Components

- `README.md`: add the fresh-clone quickstart, complete common prerequisite
  boundary, GHCR consumer/publisher distinction, and cold/warm expectations.
- `recipes/tcpdump/x86_64/README.md`: make both user-facing dispatcher commands
  unambiguous after tcpdump became multi-architecture.

## Implementation Sequence

1. Re-read the live recipe catalog and current root README immediately before
   editing so concurrently completed architecture recipes appear in the
   quickstart and links without hard-coding a recipe count.
2. Correct the two x86-64 tcpdump commands and audit every command in the root
   and current recipe READMEs against the dispatcher's unique-selection rule.
3. Add the concise fresh-clone, prerequisite, GHCR, cold/warm, and foreign-
   architecture guidance to the root build section without mixing in the
   maintainer publication procedure.
4. Inspect both changed documents against the existing source-input,
   build-pipeline, and build-environment authorities for contradictory offline,
   authentication, fallback, or cache claims. Run validation, then commit and
   push only the two documentation paths.

## Validation

- Run `git diff --check` and inspect the rendered Markdown structure and all
  relative links in the two changed documents.
- Compare every `./build.sh` command in `README.md` and the current
  `recipes/*/*/README.md` files with `./build.sh list`; require an architecture
  wherever a tool has multiple catalog rows.
- Require `git grep` over the authoritative user documents to find no bare
  `./build.sh tcpdump` or abbreviated x86-64 tcpdump `BUILD_JOBS` example.
- Run `./validate.sh`, which already composes catalog and source validation,
  unit tests, dispatcher listing, tracked shell syntax, and artifact-manifest
  checksum validation.
- Confirm the diff contains only `README.md` and
  `recipes/tcpdump/x86_64/README.md`; no artifact rebuild is required because
  this plan changes documentation only.

## Success Criteria

- A new user can copy the documented clone/list/build sequence and knows the
  common host boundary before starting compilation.
- Documentation clearly says that GHCR supplies the public, immutable,
  pre-provisioned build environment, materially reducing setup and repeat-build
  work without distributing utility binaries or requiring ordinary users to
  publish or authenticate.
- The local-source guarantee is not confused with a fully offline build: cold
  image pulls, conditional privileged binfmt registration, and the exceptional
  AArch64 smoke-kernel download are explicit.
- Warm-cache acceleration and potentially slow emulated compilation are
  described without a fixed performance promise.
- Every build command in the current user authorities selects exactly one
  enabled catalog row, including both x86-64 tcpdump examples.
- Build behavior, builders, recipes, catalogs, trust records, checksums, and
  artifact bytes remain unchanged.

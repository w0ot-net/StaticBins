# Plan: Admit Static PIE as a First-Class Artifact Profile

## Summary

Define classic static `ET_EXEC` and validated static PIE `ET_DYN` as equally
acceptable repository artifact profiles while continuing to reject dynamically
loaded PIE. Keep each recipe responsible for selecting and enforcing one exact
profile so toolchain drift still fails closed. Strengthen the sole current
static-PIE recipe, AArch64 GDB, to enforce the complete profile without
converting existing `ET_EXEC` artifacts.

## Problem

The stable artifact contract requires a recipe-selected executable type, but it
does not explain that `ET_DYN` can be a self-contained static PIE rather than a
dynamically linked executable. Most recipes therefore force `-no-pie` and
validate `ET_EXEC`, while AArch64 GDB deliberately produces static PIE and only
checks `ET_DYN`, absence of an interpreter, and absence of `DT_NEEDED` entries.
That check rejects ordinary dynamic PIE but does not independently prove the
PIE marker, a usable entry point, an executable load segment, or absence of text
relocations.

The ambiguity encourages future recipes to use `-no-pie` merely to make an ELF
look conventionally static. It also makes `ET_DYN` appear forbidden even though
the repository already distributes and target-tests one valid static PIE.

## Scope

In scope:

- Define two allowed release profiles: classic static `ET_EXEC` and static PIE
  `ET_DYN`, with the common interpreter, dependency, architecture, ABI,
  stripping, and target-smoke requirements preserved.
- Require a static PIE to have a nonzero entry point, an executable `PT_LOAD`,
  the ELF `DF_1_PIE` marker, no `PT_INTERP`, no `DT_NEEDED`, and no `DT_TEXTREL`
  or `DF_TEXTREL` indication.
- Require each recipe to choose and validate one profile rather than accepting
  either type opportunistically after a toolchain-output change.
- Make explicit `-no-pie` a reviewed compatibility or toolchain choice for new
  recipes and future link-policy changes, not proof of static linkage.
- Bring the existing AArch64 GDB static-PIE validation into conformance and
  rebuild that artifact through its normal Buildx/QEMU path.

Out of scope:

- Converting any current `ET_EXEC` artifact to static PIE or removing existing
  `-no-pie` flags solely to obtain ASLR.
- Rebuilding or editing the other 23 recipes, their artifacts, or their
  tool-owned smoke binaries.
- Changing builder validation probes; they test locked compiler and library
  capabilities rather than define the distributed-artifact profile.
- Adding an ELF profile to either catalog, making root offline validation parse
  ELF files, or creating a repository-wide validation framework.
- Promising ASLR on every kernel or measuring security, startup, size, or
  compatibility differences between the profiles.
- Adding new AArch64 GDB functional coverage beyond its existing target version
  execution; that independent smoke-test expansion is not required to prove
  static-PIE relocation and startup.
- Changing source, builder, feature, license, or trust policy.

## Design

Treat executable type and static linkage as separate facts. Repository policy
admits both profiles, but a reviewed recipe selects exactly one and rejects a
silent switch to the other. Both profiles must have the correct machine, ELF
class, endianness, ABI, and stripping state; must lack a requested program
interpreter and every `DT_NEEDED` entry; and must pass the existing
target-architecture version and recipe-owned smoke tests.

For a recipe that selects static PIE, require all of the following from
`readelf` rather than trusting the word `pie` in `file` output:

- ELF type `DYN` and a nonzero entry-point address;
- at least one executable `LOAD` segment, checked using wide program-header
  output so flags remain on the same line;
- `FLAGS_1` containing `PIE` (`DF_1_PIE`);
- no requested program interpreter or `NEEDED` dynamic tag; and
- no `TEXTREL` tag or dynamic `FLAGS` value containing `TEXTREL`.

The existing target smoke test remains the final proof that the static runtime
can relocate and execute on the promised architecture. An `ET_DYN` shared
object or dynamically loaded PIE must fail even when its machine field is
correct.

Keep current `ET_EXEC` recipes and flags unchanged. The prospective contributor
rule is narrower: a new recipe, or an existing recipe whose final-link policy is
otherwise being changed, must not add or retain explicit `-no-pie` merely to
satisfy staticness. If it selects `ET_EXEC` through an explicit non-PIE switch,
its recipe README must state the concrete compatibility or toolchain reason.
This preserves current artifacts without making their historical link flags the
default for future tools and architectures.

Give AArch64 GDB one executable, POSIX-shell validator under its recipe
directory. The validator accepts a binary path and owns the complete AArch64
static-PIE structural checks, including machine and stripping. Copy it into the
builder stage for the guest-side post-link check and invoke the same tracked
file from the host script for both the exported candidate and installed output.
This replaces two partial copies of the same invariant without introducing a
generic cross-recipe interface. Keep the existing target version execution
unchanged.

Changing the recipe requires a real rebuild. The link inputs and flags are not
changing, so no byte change is intended. If the normal build nevertheless
produces different validated bytes, retain that installed output and update
`artifacts/SHA256SUMS` rather than claiming exact reproducibility. The existing
`TRUST.md` row contains no hash and its recipe-validation statement remains
factual after the required successful rebuild, so it does not change.

## Affected Components

- `AGENTS.md`: define both accepted artifact profiles, the static-PIE checks,
  and the prospective rule for explicit `-no-pie`.
- `doc/architecture/artifacts/ARTIFACT_CONTRACT.md`: own the stable separation
  between executable type and static linkage and the complete profile
  invariants.
- `doc/adding-a-binary.md`: require a new or intentionally relinked recipe to
  select, validate, and document its release profile.
- `recipes/gdb/aarch64/{Dockerfile,build-in-container.sh,build.sh,README.md}`:
  replace duplicated partial checks with the complete tool-owned static-PIE
  validator and document the selected profile.
- `recipes/gdb/aarch64/validate-elf.sh`: provide the single guest/host AArch64
  static-PIE structural validator.
- `artifacts/aarch64/gdb` and `artifacts/SHA256SUMS`: accept the required
  rebuild output and update its manifest record only if the rebuilt bytes
  differ.

## Implementation Sequence

1. Record the current AArch64 GDB hash and `readelf` profile, then add the
   recipe-owned validator and make both guest and host paths call it.
2. Update the artifact contract, contributor procedure, agent guidance, and
   AArch64 GDB README around the two-profile policy and prospective `-no-pie`
   rule.
3. Run shell syntax and direct validator checks against the committed AArch64
   GDB before compilation; require the validator to reject the AArch64
   `ET_EXEC` GDBserver artifact as the wrong selected profile.
4. Warn that the target build may exceed ten minutes, then run
   `./build.sh gdb aarch64` through the locked builder and its supported target
   execution path. Compare the resulting bytes with the recorded hash and make
   only the conditional manifest update described above.
5. Re-run focused ELF inspection and repository validation, audit the final
   diff against the scope boundary, then commit and push only the accepted
   implementation and completed-plan paths.

## Validation

- Run `sh -n` on the new validator and guest build script, `bash -n` on the host
  build script, and `git diff --check`.
- Run the new validator directly on `artifacts/aarch64/gdb`; independently
  confirm `DYN`, a nonzero entry point, an executable `LOAD`, `FLAGS_1` with
  `PIE`, no interpreter, no `NEEDED`, no text relocations, AArch64 machine, and
  stripped state with `file` and `readelf`.
- Require the AArch64 static-PIE validator to reject
  `artifacts/aarch64/gdbserver`, proving that a valid static `ET_EXEC` artifact
  does not satisfy a recipe that selected the PIE profile.
- Run `./build.sh gdb aarch64` and require its existing target version execution
  to pass under the recipe's supported native or Buildx/QEMU path.
- Require the installed artifact to match the fully validated candidate. If
  its SHA-256 changed, update the one manifest row and re-run
  `sha256sum -c artifacts/SHA256SUMS`; otherwise require no artifact or manifest
  diff.
- Run `./validate.sh` and confirm all catalog, source-authentication, license,
  trust, shell-syntax, artifact-manifest, dispatcher, and unit-test checks pass.
- Search live policy and contributor documentation for claims that PIE or all
  `ET_DYN` executables are dynamically linked, and confirm the final diff does
  not modify other recipes, artifacts, builders, catalogs, source inputs,
  feature profiles, or licenses.

## Success Criteria

- Repository policy explicitly accepts recipe-selected classic static
  `ET_EXEC` and properly validated static PIE while rejecting dynamically
  loaded PIE and shared objects.
- Staticness is established by interpreter, dependency, relocation, structure,
  and target-execution checks rather than `-static`, `-no-pie`, `file` wording,
  or ELF type alone.
- AArch64 GDB enforces the complete static-PIE profile through one tool-owned
  validator in guest, candidate, and installed-output validation and passes its
  real target smoke tests.
- New recipes and future link-policy changes do not force non-PIE output without
  a documented compatibility or toolchain reason.
- Existing `ET_EXEC` recipes and artifacts remain accepted without a conversion
  campaign, and no unrelated builder, recipe, artifact, or policy work is
  absorbed.

## Execution Notes

- Defined classic static `ET_EXEC` and static PIE `ET_DYN` as recipe-selected
  release profiles in the repository contract, artifact authority, and
  contributor procedure. Explicit `-no-pie` is no longer treated as evidence
  of static linkage or a default for new and reviewed link policies.
- Added one executable AArch64 GDB validator and used it for the guest output,
  exported host candidate, and installed artifact. It enforces ELF64
  little-endian AArch64 `ET_DYN`, a nonzero entry point, an executable
  `PT_LOAD`, `DF_1_PIE`, no `PT_INTERP`, `DT_NEEDED`, or text relocations, and
  stripped output.
- Rebuilt AArch64 GDB 17.2 through its locked Buildx/QEMU path. The target
  `--version` smoke test passed, and the installed artifact reproduced the
  committed SHA-256 exactly:
  `5e96e51367020e6be6e2cb0a7f0014573da838a8f7d1d099fd2e5a4a55c820ab`.
  No artifact, checksum manifest, or trust-record update was required.
- Shell syntax checks, direct positive validation, negative rejection of the
  AArch64 `ET_EXEC` GDBserver artifact, all artifact checksum checks,
  `git diff --check`, and `./validate.sh` passed. Repository validation covered
  28 enabled recipes and 25 tests.
- No material implementation deviation was required. Four recipes were added
  concurrently after the plan recorded 24 total recipes, making the literal
  "other 23" count stale; the intended boundary remained intact because no
  other recipe, artifact, builder, catalog, source, feature, or license was
  changed by this implementation.
- Implementation commit: `0801f37`.

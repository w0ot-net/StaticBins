# Plan: Add GNU objdump Across Ready Architectures

## Summary

Add GNU Binutils 2.47 `objdump` as a stripped static executable for `aarch64`,
`armv7`, `x86`, and `x86_64`. Use the signed official release, the existing
locked builders, a native-format-focused feature profile, and a target smoke
test that proves header, symbol-table, and disassembly behavior. Keep `objdump`
as a normal independently rebuildable artifact rather than introducing a
Binutils bundle or utility container.

## Problem

The repository does not provide a standalone object-file inspection and
disassembly utility. Existing tools can debug or inspect ELF metadata in
specific workflows, but they do not replace the familiar `objdump` interface.

Binutils builds many sibling programs and optional integrations from one source
tree. A clean recipe must export only `objdump`, pin its supported feature
surface, inventory the archives in its static link, and exercise real
disassembly instead of treating `--version` as sufficient validation.

## Scope

In scope:

- Add `artifacts/<architecture>/objdump` for all four ready architectures.
- Authenticate the official Binutils 2.47 release and retain its exact source,
  detached signature, minimal signer keyring, licenses, and link provenance in
  every recipe.
- Build a static PIE with the native BFD target profile, compressed-section
  support from already locked static libraries, and no runtime plugins, NLS,
  or debuginfod dependency.
- Test file-header reporting, symbol discovery, section reporting, and actual
  disassembly of a controlled target object on every host architecture.
- Preserve a cacheable Binutils compile boundary that sibling `readelf` and
  `nm` recipes may reuse when those independent plans are executed together.

Out of scope:

- `readelf`, `nm`, `ar`, `as`, `ld`, `objcopy`, `strip`, `strings`, `addr2line`,
  or any other Binutils executable.
- A `binutils` archive/bundle artifact, multi-output catalog rows, symlinks,
  shell dispatch wrappers, or changes to generic recipe orchestration.
- Enabling every cross-architecture BFD target, LTO plugins, debuginfod, NLS,
  CTF-specific promises, or performance/coverage benchmarking.
- Publishing a utility runtime image, changing the reusable builders, or
  claiming byte-for-byte reproducibility or independent attestation.

## Design

Use the official HTTPS `binutils-2.47.tar.xz` release archive, accepted SHA-256
`154ab23b60070e8f27013c22977f1129425d67d1e8acd6e13010e617811e4cff`,
and detached signature from the GNU Binutils directory. The accepted archive
is 29,034,716 bytes. Declare `pgp` and track an export-minimal keyring for Nick
Clifton's exact GNU-keyring fingerprint
`3A24BC1E8FB409FA9F14371813FCEF89DD9E3C4F`; require the published RSA/SHA-512
signature to verify with `gpgv` before extraction.

The current builders already contain the required compiler, autotools support,
zlib/zstd development and static archives, and standard build tools. Do not
revise or publish builders. Configure an out-of-tree Binutils build for the
matching musl host triplet with static libraries/programs, NLS/plugins/
debuginfod disabled, and only the BFD/binutils subprojects needed by the
requested utility. Keep the default native BFD target family rather than
`--enable-targets=all`; document that this artifact is optimized for inspecting
objects used on its host architecture, not as a universal cross-toolchain.

Use the narrowest reliable upstream make boundary. It is acceptable for a
temporary build tree to compile sibling `binutils/` programs when upstream's
dependency graph requires `all-binutils`, but the Docker artifact stage and
host installer export only `objdump`. Keep source verification and the common
compile stage content-identical to the future `readelf` and `nm` recipes where
the inputs and flags truly match so BuildKit can reuse completed compilation;
do not create a shared recipe owner or make one artifact command mutate another
artifact.

Compile with `-O2 -pipe`, use the repository's i686/CMOV/SSE2 flags on `x86`,
link with `-static` and a final linker map, and select static PIE `ET_DYN` as
the exact release profile. Require a nonzero entry point, executable `PT_LOAD`,
`DF_1_PIE`, no `PT_INTERP`, no `DT_NEEDED`, no text relocations, correct target
ABI, and a stripped output. Stop if a locked builder cannot produce that
profile; do not add `-no-pie`, mutable package installation, or a dynamic
fallback.

Review the Binutils 2.47 program and in-tree library license files instead of
assigning one blanket license to every internal archive. The final-link
validator maps every source-built BFD/opcodes/libiberty or other archive to the
accepted source, component version, applicable license text, and source
evidence, and maps every builder archive to its exact APK owner, version,
license, reviewed text, and immutable aports source URL.

Build a small unstripped target object containing a uniquely named function and
data symbol. On the target architecture, require exact 2.47 version output;
use `objdump -f` and `-h` to identify the fixture, `-t` to find the symbols, and
`-d` to emit a labeled disassembly for the known function. Assert structural
markers rather than architecture-specific mnemonic spelling so the same test
owns all four architectures without hiding machine/ABI checks.

## Affected Components

- `recipes/objdump/{aarch64,armv7,x86,x86_64}/`: add Dockerfiles, host and
  guest builds, fixture/smoke tests, READMEs, signed source locks and inputs,
  and component-aware license/link inventories.
- `recipes/catalog.tsv`: add four enabled `objdump` rows.
- `artifacts/{aarch64,armv7,x86,x86_64}/objdump`: add four validated
  executables.
- `artifacts/SHA256SUMS`: add sorted exact checksums for the four artifacts.
- `TRUST.md`: add four upstream-PGP source records with the exact Nick Clifton
  fingerprint and no independent artifact evidence unless it is actually
  produced.
- `README.md`: add `objdump` to the concise supported-tool list.

## Implementation Sequence

1. Re-fetch the official archive, signature, and GNU keyring into temporary
   storage; verify the accepted checksum, size, exact signer fingerprint and
   signature, then review the program and internal-library license texts before
   committing identical mode-100644 inputs to the four recipes.
2. Implement and really build the x86-64 recipe first. Pin the configure
   summary, static-PIE/link inventory, exact version, and fixture disassembly
   test before copying the proven shape to non-native architectures.
3. Add AArch64, ARMv7, and x86 owners, changing only platform/triplet, target
   ELF/ABI checks, and the required x86 CPU flags. Keep source, feature flags,
   fixture behavior, and cacheable compile steps equivalent.
4. Before the emulated builds, report the expected duration. Build and smoke
   test each remaining target once through its committed builder digest,
   preserving BuildKit cache and diagnostic output rather than repeating a
   known-good compilation for late validation.
5. Review output sizes, add all four catalog rows and artifacts atomically,
   update checksums/trust/README, run focused and repository validation, then
   commit and push only this rollout and its completed-plan record.

## Validation

- Run `bash -n`/`sh -n` for new scripts, `git diff --check`, patch/input mode
  checks, and `python3 scripts/recipes.py validate` after explicit staging.
- Verify every archive checksum and the detached signature with only the
  tracked minimal keyring; require the exact full fingerprint and fail closed.
- Inspect configure output to require the intended static native-target profile
  and disabled optional runtime integrations.
- Parse the final linker map and require complete component-level source,
  version, license, and evidence coverage for every linked archive.
- For candidates and installed outputs, require exact machine, class,
  endianness, ABI, stripped static PIE invariants, ARMv7 hard-float details,
  x86 i686 baseline compilation, and candidate/installed hash equality.
- On each target, require Binutils 2.47 and successful `objdump -f`, `-h`, `-t`,
  and `-d` checks against the controlled object, including the known function
  label in disassembly.
- Run `sha256sum -c artifacts/SHA256SUMS` and `./validate.sh`; confirm no other
  Binutils artifact, utility image, builder, catalog schema, generic script, or
  architecture contract changed.

## Success Criteria

- `./build.sh objdump <architecture>` rebuilds each committed executable from
  tracked authenticated source and the existing immutable builder.
- All four files are stripped static PIEs for their promised host architecture
  and correctly inspect and disassemble the target fixture.
- The native-target feature boundary and omitted runtime integrations are
  explicit, and every linked input has reviewed source/license evidence.
- Only `objdump` is distributed; the rollout adds no Binutils bundle, sibling
  executable, runtime image, mutable dependency, or generic repository
  abstraction.

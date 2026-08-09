# Plan: Add GNU nm Across Ready Architectures

## Summary

Add GNU Binutils 2.47 `nm` as a stripped static executable for `aarch64`,
`armv7`, `x86`, and `x86_64`. Use the authenticated official release and
existing locked builders, and validate symbol classification, filtering,
sorting, and archive-member reporting on each target. Treat `nm` as an
independent artifact and explicitly omit runtime LTO plugins.

## Problem

The repository lacks a portable static symbol-table inspection tool. That is a
common need when diagnosing stripped versus unstripped objects, resolving link
failures, or inspecting libraries on systems where the dynamic Binutils package
cannot run.

Binutils `nm` can acquire optional plugin behavior and supports several object
formats through BFD. Without an explicit build and smoke contract, a nominally
static binary could still vary by builder contents or appear functional while
failing to classify real object/archive symbols.

## Scope

In scope:

- Add `artifacts/<architecture>/nm` for AArch64, ARMv7, x86, and x86-64.
- Authenticate and retain Binutils 2.47 source/signature/key evidence and all
  required component licenses and final-link provenance.
- Build a native-BFD-profile static PIE with compressed-section support and no
  runtime plugin, NLS, or debuginfod dependency.
- Functionally test defined, undefined, global, local, data, and text symbols,
  filtering/sorting, and static archive member labels on every target.
- Keep common Binutils compilation cache-compatible with the independent
  `objdump` and `readelf` plans without adding shared artifact ownership.

Out of scope:

- `objdump`, `readelf`, or any other Binutils executable; bundle archives,
  symlink sets, wrappers, or catalog schema changes.
- LTO object inspection through GCC/LLVM plugins, universal cross-target BFD
  support, demangling guarantees beyond the built-in upstream profile, or
  parsing symbols from corrupt/adversarial corpus suites.
- Builder changes, runtime images, generic recipe refactors, benchmarking,
  exact-rebuild qualification, or provenance attestation.

## Design

Pin official GNU `binutils-2.47.tar.xz`, SHA-256
`154ab23b60070e8f27013c22977f1129425d67d1e8acd6e13010e617811e4cff`,
size 29,034,716 bytes, and its detached signature. Declare `pgp`; track a
minimal keyring containing only Nick Clifton's GNU-keyring identity at full
fingerprint `3A24BC1E8FB409FA9F14371813FCEF89DD9E3C4F`, and require the published
RSA/SHA-512 signature to verify before extraction.

The existing locked builders already contain the build tools and static
zlib/zstd libraries needed by this profile, so builders remain unchanged.
Configure out of tree for the matching musl host, build static programs and
libraries, disable NLS/plugins/debuginfod, and limit BFD to its native target
family. Document that external LTO plugin objects are deliberately unsupported
and that the artifact is intended primarily for objects/libraries used on its
host architecture rather than as a universal cross-toolchain.

Use the narrowest reliable upstream target, permitting temporary
`all-binutils` compilation when required. Only `nm` is exported and installed.
Make the verified source/configuration/common compilation layers identical to
sibling Binutils recipes where inputs match, allowing BuildKit to reuse the
expensive work when the plans are executed together; do not make `./build.sh nm
<architecture>` alter `objdump` or `readelf`.

Compile with `-O2 -pipe` and the required i686/CMOV/SSE2 flags on x86. Link
with `-static` and a final map, select static PIE `ET_DYN`, strip the release
candidate, and enforce every target and static-PIE invariant before and after
installation. If the selected builder cannot satisfy that exact profile, stop
instead of using `-no-pie`, dynamic fallback libraries, or recipe-time package
resolution.

Review the `nm` program license and each linked source-built Binutils archive
against the 2.47 source notices. The linker-map inventory must distinguish
those internal components from builder archives and give every entry its exact
version, applicable license text, and immutable source evidence.

Create two target fixtures: an unstripped relocatable object with uniquely
named global text/data symbols, a local text symbol, and an unresolved external
reference; and a static archive containing named members. Run the candidate on
the target architecture and require exact 2.47 version output, expected symbol
type letters in a stable output format, `--defined-only` and `--undefined-only`
filtering, deterministic name/numeric sort behavior, and correct archive/member
labels. Avoid C++ demangling and toolchain-generated incidental symbol names in
the acceptance assertions.

## Affected Components

- `recipes/nm/{aarch64,armv7,x86,x86_64}/`: add Dockerfiles, host/guest builds,
  object/archive fixtures and smoke tests, READMEs, PGP source locks/inputs,
  and component-aware license/link inventories.
- `recipes/catalog.tsv`: add four enabled `nm` rows.
- `artifacts/{aarch64,armv7,x86,x86_64}/nm`: add four validated executables.
- `artifacts/SHA256SUMS`: add four sorted exact checksum records.
- `TRUST.md`: add four signed Binutils source records with Nick Clifton's exact
  fingerprint and no independent artifact evidence unless produced.
- `README.md`: add `nm` to the concise supported-tool list.

## Implementation Sequence

1. Re-fetch the archive, detached signature, and GNU signer evidence into
   temporary storage; verify checksum, size, full fingerprint/signature, and
   all linked-component licenses before committing identical reviewed inputs.
2. Implement x86-64 first and run a real build. Lock configure output, final
   link ownership, static-PIE checks, and the object/archive symbol smoke test
   before replicating the recipe.
3. Add AArch64, ARMv7, and x86 recipes with the same source, feature profile,
   fixtures, and cacheable compilation; vary only platform/triplet, target ABI
   validation, and explicit x86 CPU flags.
4. Warn about expected emulation duration, then build and smoke-test each
   remaining architecture exactly once through its committed builder. Preserve
   cache/diagnostics for validation retries instead of restarting compilation.
5. Review sizes, add all four catalog rows and artifacts atomically, update
   checksums/trust/README, run focused/full validation, and commit/push only
   this rollout and completed-plan record.

## Validation

- Run shell syntax checks, `git diff --check`, tracked-input/mode checks, and
  staged `python3 scripts/recipes.py validate`.
- Verify the exact source SHA-256 and PGP signature with only the minimal
  keyring and required full fingerprint.
- Require configure output to match the native, static, plugin-free feature
  contract and the final map to have complete source/version/license evidence.
- Validate correct machine, class, endianness, ABI, stripping, full static-PIE
  invariants, ARMv7 hard-float, x86 i686 baseline, and candidate/installed hash
  equality.
- On every target, require Binutils 2.47 plus exact symbol classifications,
  defined/undefined filtering, sorting, and archive-member output from the
  controlled fixtures.
- Run `sha256sum -c artifacts/SHA256SUMS` and `./validate.sh`; confirm no LTO
  plugin, sibling Binutils executable, runtime image, builder, generic script,
  or architecture contract changed.

## Success Criteria

- `./build.sh nm <architecture>` rebuilds all four committed artifacts from
  tracked signed source using only the existing immutable builders.
- Each artifact is a stripped static PIE for its promised host and correctly
  reports the controlled object and archive symbols on that target.
- Native-format/plugin limitations and every linked component's license/source
  evidence are explicit and enforced.
- Only `nm` is distributed, without a Binutils bundle, sibling output, mutable
  dependency, utility image, or generic repository abstraction.

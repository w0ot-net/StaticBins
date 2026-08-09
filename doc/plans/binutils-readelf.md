# Plan: Add GNU readelf Across Ready Architectures

## Summary

Add GNU Binutils 2.47 `readelf` as a stripped static executable for `aarch64`,
`armv7`, `x86`, and `x86_64`. Authenticate the signed official release, use the
existing locked builders, and functionally validate ELF headers, sections,
symbols, program headers, and DWARF data on every target. Keep the rollout
independent from other Binutils utilities and from generic repository changes.

## Problem

The repository uses `readelf` as a host-side validation prerequisite but does
not distribute a target-side static copy. Users diagnosing a constrained system
therefore cannot rely on this repository to inspect ELF structure without
installing a dynamic package.

A valid solution must prove more than version output: it must parse meaningful
ELF structures and debug information while remaining self-contained. It must
also avoid accidentally distributing the rest of the Binutils suite or making
runtime data and plugin support implicit.

## Scope

In scope:

- Add `artifacts/<architecture>/readelf` for all four ready architectures.
- Track and verify the official signed Binutils 2.47 source and retain complete
  component/license/link evidence in each recipe.
- Build a static PIE with compressed-section support from already locked
  static libraries and no NLS, runtime plugin, or debuginfod dependency.
- Test ELF file/program headers, sections, symbols, and DWARF inspection using
  a controlled target fixture on every architecture.
- Preserve a cacheable Binutils compile boundary usable by independent
  `objdump` and `nm` rollouts without coupling artifact ownership.

Out of scope:

- `objdump`, `nm`, or any other Binutils executable; a suite archive, symlink
  set, wrapper, or multi-output catalog model.
- Promising support for non-ELF object formats, every optional CTF feature,
  split-debug/debuginfod retrieval, LTO plugins, localization, or external
  debug-file discovery across arbitrary target root filesystems.
- Builder changes, utility runtime images, generic validation refactors,
  performance tests, exact-rebuild claims, or attestations.

## Design

Use official `https://ftp.gnu.org/gnu/binutils/binutils-2.47.tar.xz` at SHA-256
`154ab23b60070e8f27013c22977f1129425d67d1e8acd6e13010e617811e4cff`
and size 29,034,716 bytes, together with its detached signature. Declare `pgp`
and require `gpgv` to identify Nick Clifton's exact GNU-keyring fingerprint
`3A24BC1E8FB409FA9F14371813FCEF89DD9E3C4F`; retain only an export-minimal
tracked keyring and fail on any RSA/SHA-512 verification mismatch.

The existing architecture builders already provide the compiler, build tools,
and static zlib/zstd inputs needed for the selected profile. Configure an
out-of-tree build for the matching musl host with static libraries/programs,
NLS/plugins/debuginfod disabled, and only the Binutils subprojects needed by
`readelf`. Keep compressed ELF/DWARF section handling enabled and document any
upstream feature that the real configure result shows is omitted. Do not
resolve new packages inside a recipe or revise builders speculatively.

Use the narrowest stable upstream make target. A temporary `all-binutils` build
is acceptable when required by upstream dependencies, but only `readelf` may
cross the scratch-artifact boundary or replace a committed file. Keep the
common source/configuration/compile layer content-identical to sibling Binutils
recipes where truthful so BuildKit can reuse work; each public command still
owns and validates exactly one artifact.

Compile with `-O2 -pipe`, add the repository's i686/CMOV/SSE2 flags on x86,
link with `-static` plus a final map, and pin static PIE `ET_DYN`. Enforce the
full static-PIE artifact contract, target machine/class/endianness/ABI,
stripping, and installed/candidate byte identity. A failure to produce this
profile is a stop condition, not permission to force `-no-pie`, install mutable
packages, or accept dynamic dependencies.

Review the license of `readelf` and each source-built internal archive from the
2.47 tree individually. Final-link evidence must distinguish Binutils source
components from exact builder-owned archives and map each to its version,
applicable reviewed license text, and immutable source evidence.

Compile an unstripped target fixture with a named function, initialized data,
at least one loadable segment, and DWARF information. In the target container,
check exact 2.47 version output, then require `readelf -hW`, `-lW`, `-SW`, and
`-sW` to report the expected target structure and symbol. Require a focused
`--debug-dump=info` assertion for the known source/function marker so compressed
and debug parsing are exercised without depending on host files or network
retrieval.

## Affected Components

- `recipes/readelf/{aarch64,armv7,x86,x86_64}/`: add Dockerfiles, host/guest
  builds, ELF/DWARF fixture and smoke tests, READMEs, PGP source locks and
  tracked inputs, and component-aware license/link inventories.
- `recipes/catalog.tsv`: add four enabled `readelf` rows.
- `artifacts/{aarch64,armv7,x86,x86_64}/readelf`: add four validated static
  executables.
- `artifacts/SHA256SUMS`: add four sorted exact checksum records.
- `TRUST.md`: add four Binutils upstream-PGP source records with the exact
  signer fingerprint and no independent artifact evidence unless produced.
- `README.md`: add `readelf` to the concise supported-tool list.

## Implementation Sequence

1. Re-fetch and verify the official archive, signature, GNU keyring signer,
   accepted checksum/size, and relevant component licenses in temporary
   storage; commit identical reviewed mode-100644 inputs to all four recipes.
2. Build x86-64 first and lock the actual configure feature summary, linker-map
   inventory, static-PIE validation, and ELF/DWARF fixture assertions before
   replicating the recipe.
3. Add AArch64, ARMv7, and x86 recipes with equivalent source, configuration,
   fixture, and cacheable compile behavior; vary only platform/triplet,
   architecture/ABI validation, and x86 baseline flags.
4. Give the required duration warning, then run each remaining emulated build
   and target smoke once using its committed builder digest. Retain caches and
   diagnostic state for late-step retries rather than recompiling.
5. Inspect artifact sizes, land all four rows/artifacts together, update the
   manifest/trust/README, run focused and full validation, and commit/push only
   this rollout plus its completed-plan record.

## Validation

- Run new-script syntax checks, `git diff --check`, source evidence/mode checks,
  and staged `python3 scripts/recipes.py validate`.
- Verify SHA-256 and the detached release signature using only the minimal
  keyring and exact full fingerprint.
- Require configure output to match the static, compressed-section-capable
  feature profile with runtime integrations disabled.
- Require the final map to have exact reviewed source/version/license evidence
  for every internal and builder archive.
- Validate the candidate and installed artifact's machine, class, endianness,
  ABI, stripping, full static-PIE invariants, ARMv7 hard-float details, x86 CPU
  baseline, and identical SHA-256.
- On every target require version 2.47 and exact fixture markers from headers,
  program headers, sections, symbols, and DWARF-info commands.
- Run `sha256sum -c artifacts/SHA256SUMS` and `./validate.sh`; confirm no sibling
  Binutils output, utility image, builder, generic validator, or architecture
  policy changed.

## Success Criteria

- `./build.sh readelf <architecture>` rebuilds all four artifacts from tracked
  signed source and the existing immutable builders.
- Every output is a stripped static PIE for its advertised host and correctly
  inspects the controlled ELF and DWARF structures on that target.
- Optional integrations and license/link provenance are explicit and fail
  closed; no runtime shared library, data download, or plugin is required.
- Only `readelf` is distributed, with no suite bundle, sibling executable,
  builder publication, or new repository abstraction.

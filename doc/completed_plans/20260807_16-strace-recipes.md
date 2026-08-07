# Plan: Add strace Recipes for Both Architectures

*Distilled: 2026-08-07*

## Summary

Replace the legacy x86-64 strace and add AArch64 strace with version 6.16
recipes. Keep the intentionally self-contained native-personality feature
profile, authenticate the retained archive by checksum, and require a real
ptrace test that traces deterministic syscalls on each target architecture
before artifact installation.

This plan depends on `01-multi-architecture-recipe-selection.md`,
`02-narrow-tcpdump-assurance-selection.md`, and
`03-expand-reusable-builders.md`.

## Problem

`artifacts/x86_64/strace` is a stripped static strace 6.16 executable, but its
source/build/license provenance is unknown and its optional m32/mx32
personalities are absent. There is no AArch64 artifact. Static ELF inspection
and `--version` do not prove that ptrace works inside the intended container
execution path.

## Scope

In scope:

- Preserve strace 6.16 and build native 64-bit decoding without m32/mx32
  personalities, stack unwinding, SELinux contexts, or external libiberty.
- Add enabled AArch64 and x86-64 conventional recipes using the reusable locked
  builders.
- Retain the official `strace-6.16.tar.xz`, SHA-256
  `3d7aee7e4f044b2f67f3d51a8a76eda18076e9fb2774de54ac351d777d4ebffa`,
  with explicit `checksum-only` authentication. Do not adopt the available
  detached signature until the exact release signer key has separately
  authenticated official full-fingerprint evidence.
- Build stripped static native `ET_EXEC` files, use bundled Linux UAPI headers
  deliberately, and reconcile every final linked archive/license.
- Run the candidate as the direct parent tracer of a deterministic child and
  assert expected syscall output and exit behavior.
- Replace/add artifacts, checksum records, recipe notices, and concise trust
  documentation while retaining `Not verified` status.

Out of scope:

- Upgrading strace, supporting 32-bit tracee personalities, stack traces,
  SELinux contexts, or broad privileged/container-escape tests.
- Importing a signing key from an unauthenticated keyserver or falling back to
  checksum-only after an attempted PGP verification failure; this plan chooses
  checksum-only explicitly before build.
- Exact-rebuild qualification, attestation workflow changes, or a utility
  image.

## Design

Create `recipes/strace/{aarch64,x86_64}/` with the same single-source recipe
shape used elsewhere. Track the exact official archive under each `sources/`
directory and set `SOURCE_AUTHENTICATION=checksum-only`; omit signature/key
fields so validation cannot imply a PGP claim. Document the official detached
signature and the unadopted signer-key evidence limitation in the notice rather
than shipping an unusable keyring.

Configure with native build/host triplets, optimization, `-static -no-pie`,
`--enable-bundled=yes`, `--enable-mpers=no`, `--enable-stacktrace=no`,
`--without-libdw`, `--without-libunwind`, `--without-libiberty`, and
`--without-libselinux`. These explicit switches prevent optional packages in a
reusable builder from silently changing the feature set. Generate a linker map
and require every archive to map to the strace release or an exact Alpine
package/version/license/source row, including GCC/musl inputs and the bundled
kernel-header licensing notices.

The host scripts follow the established temporary Buildx export and atomic
install contract. Validate correct machine, `ET_EXEC`, stripped state, no
interpreter, and no `DT_NEEDED`, then run a target-platform smoke script. The
smoke script checks exact 6.16 version/feature output and executes the candidate
as the parent tracer of a small shell or compiled fixture that performs known
`write`, `openat`, and exit syscalls. Require a trace file containing the
expected marker/syscalls and successful traced-program status. Use a timeout;
do not add `SYS_PTRACE` capability when tracing a direct child succeeds under
the normal container policy.

## Affected Components

- `recipes/strace/aarch64/*` and `recipes/strace/x86_64/*`: add source locks,
  static build/export scripts, ptrace smoke tests, READMEs, licenses/notices,
  and linked-archive inventories.
- `recipes/catalog.tsv`: add enabled strace rows for both architectures.
- `artifacts/aarch64/strace` and `artifacts/x86_64/strace`: add/replace the
  validated executables.
- `artifacts/SHA256SUMS`: add sorted checksum records for both outputs.
- `README.md`: list strace 6.16 for both architectures and link the recipe docs.
- `TRUST.md`: record the explicit checksum-only source evidence and both `Not
  verified` artifact rows, replacing the legacy no-evidence row.

## Implementation Sequence

1. Download the official 6.16 archive to temporary storage, verify its locked
   hash/size, review upstream LGPL/test/header notices, and explicitly add the
   accepted archive and required distribution material to both recipes.
2. Implement one static native build with explicit optional-feature switches,
   linker-map reconciliation, and the direct-child ptrace test.
3. Port only target triplet/platform/machine constants to the other recipe and
   run each build once, retaining cache and diagnostics for late validation.
4. Add both catalog rows, atomically add/replace artifacts, update the sorted
   manifest, and revise only the nearest root/trust documentation.

## Validation

- Run `python3 scripts/recipes.py validate` and require both strace locks to
  report checksum-only; run `python3 -m unittest tests.test_recipes`, shell
  syntax checks, `./build.sh list`, and `git diff --check`.
- Run `./build.sh strace x86_64` and `./build.sh strace aarch64` once each.
  Confirm version 6.16, documented absent optional features, correct
  machine/`ET_EXEC`, no interpreter/`DT_NEEDED`, stripped output, and complete
  final-link inventory.
- Require the target smoke test to trace the deterministic child, find the
  expected syscall/marker records, and propagate its success status without
  extra ptrace capability.
- Run `sha256sum -c artifacts/SHA256SUMS`, inspect output modes/sizes, and
  confirm only the intended legacy x86-64 strace was replaced.
- Confirm unrelated tcpdump compilation, PGP claims, attestations, and utility
  images were not added.

## Success Criteria

- Both explicit root commands rebuild strace 6.16 from retained
  checksum-verified source through immutable builders without source/package
  network resolution.
- Both committed artifacts are stripped static native executables whose
  documented feature omissions are stable and whose ptrace smoke tests trace a
  real child successfully.
- Source-authentication limitations, archive/link/license evidence, checksums,
  and `Not verified` statuses are complete for both architectures.

## Execution Notes

Completed on 2026-08-07.

- Implementation commit `3172aae` added both strace 6.16 recipes, identical
  2,674,064-byte official source archives, the project and bundled Linux UAPI
  license materials, complete final-link evidence, catalog/trust records, and
  two validated artifacts. Offline validation reports both source locks
  explicitly as `checksum-only`; no unverified signing key or signature
  fallback was introduced.
- The native evidence build established the standard Automake `all` target as
  the required ordering boundary for generated decoder headers. Its linker map
  reconciled internal `libstrace.a`, musl libc/ssp support, and GCC
  `libgcc`/`libgcc_eh`; no optional external unwind, libiberty, or SELinux
  archive entered the final link.
- The x86-64 target test traced a compiled direct child without extra
  capability, decoded its exact `openat`, marker-bearing `write`, and
  `exit_group(0)` calls, and propagated success. The 1,521,720-byte artifact at
  `7ec3134a655b55ad66b1b9f13d3da5069b2a19fff4c3e398e88e4017607045d5`
  replaces the 1,484,856-byte legacy file at
  `05518e2df031134dec0b8b066d7dd211d8262e3950467459178936b0d34ea6a4`.
- The only AArch64 compilation completed under user-mode emulation in about 12
  minutes. QEMU user mode then reported `PTRACE_TRACEME` as unimplemented, so
  the successful build layer was preserved while two tiny static smoke helpers
  were added. A generated diskless QEMU `virt` initramfs booted the pinned,
  checksum-verified Alpine 3.22.5 kernel and passed the same real direct-child
  syscall assertions. The 1,509,288-byte artifact is
  `104a2703f969396fa921e7a74bea2406c028f1774f49113007a7efddb09b6733`.
- Both distributed outputs are stripped static native `ET_EXEC` files, report
  version 6.16, use bundled Linux UAPI headers, and expose only their intended
  native-personality profiles: `no-m32-mpers no-mx32-mpers` on x86-64 and
  `no-m32-mpers` on AArch64. Stack unwinding, external libiberty demangling,
  and SELinux contexts remain absent.
- Offline validation accepted ten enabled recipes and printed exactly the two
  expected strace checksum-only notices. All 20 recipe unit tests, shell
  syntax, dispatcher listing, the complete artifact checksum manifest, and
  task diff checks passed.
- Post-push runs `31207583434` (`recipe-validation`) and `31207584233`
  (`artifact-assurance`) passed. Both tcpdump rebuild jobs were skipped because
  its trust boundary was unchanged. No utility image, PGP claim, attestation
  claim, or workflow expansion was added; both artifacts remain `Not verified`.

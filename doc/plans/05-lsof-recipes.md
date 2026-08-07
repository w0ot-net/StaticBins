# Plan: Add lsof Recipes for Both Architectures

## Summary

Replace the legacy x86-64 lsof and add AArch64 lsof with conventional recipes
for version 4.99.5. Preserve its useful Linux/RPC feature profile, use the
expanded static libtirpc-capable builders, and require a focused `/proc` test
that finds a file descriptor held by a known process before either artifact is
installed.

This plan depends on `01-multi-architecture-recipe-selection.md`,
`02-narrow-tcpdump-assurance-selection.md`, and
`03-expand-reusable-builders.md`.

## Problem

`artifacts/x86_64/lsof` is a stripped static lsof 4.99.5 with RPC and other
Linux features, but it has no recipe or source/license evidence. No AArch64
lsof is distributed. A version-only rebuild would not prove the utility can
actually inspect procfs or that every static archive in the final link is
accounted for.

## Scope

In scope:

- Preserve lsof 4.99.5 and its non-security-restricted Linux build with
  libtirpc/RPC support.
- Add two enabled catalog rows and complete AArch64/x86-64 recipe directories.
- Retain the official GitHub release asset `lsof-4.99.5.tar.gz`, SHA-256
  `4682c2491ec8b3d62f84e135afc1d9ead1bad5f034b50716f0c3826a4ee7d229`,
  under explicit `checksum-only` authentication because no detached upstream
  signature is adopted.
- Build stripped static native executables through supported configure
  variables/options, including explicit libtirpc and excluding SELinux.
- Reconcile the final link against lsof source plus exact Alpine static
  archive/package/license evidence.
- Functionally prove the binary finds a known open file held by a controlled
  process on the target architecture.
- Replace/add artifacts, checksum records, recipe notices, and bounded root
  documentation while retaining `Not verified` status.

Out of scope:

- Upgrading lsof, enabling SELinux, applying setuid/setgid bits, or weakening
  the default ability of an invoking user to inspect only what the kernel
  permits.
- Running the broad upstream test suite or requiring host `/proc` inspection
  outside an isolated target container.
- Exact-rebuild qualification, attestation jobs, utility images, or a shared
  generic smoke-test framework.

## Design

Create `recipes/lsof/{aarch64,x86_64}/` with one tracked release archive per
recipe. Record `SOURCE_AUTHENTICATION=checksum-only` and surface that limitation
in validation, the recipe README, and `TRUST.md`; do not add placeholder PGP
fields or attempt a network key lookup during normal validation.

Configure out of tree with `--disable-shared`, `--enable-static`,
`--disable-liblsof` (which suppresses installation of the separate library
while the executable continues to compile its required sources),
`--with-libtirpc`, `--without-selinux`, and the native musl build/host triplets.
Pass optimization and `-static -no-pie` through supported `CFLAGS`/`LDFLAGS`
variables rather than rewriting generated Makefiles. Require configure results
and `lsof -v` to show the intended RPC/Linux features and no unexpected
security restriction.

Generate a linker map for the executable and reconcile every archive. The
license directory must contain lsof's exact `COPYING`, musl/GCC materials, and
libtirpc plus any other actually linked package licenses with immutable Alpine
source evidence. The build fails on an extra, absent, differently owned, or
license-mismatched archive.

Each architecture host script consumes only its immutable environment lock,
builds to temporary output with Buildx, and validates the promised machine,
`ET_EXEC`, stripped state, no interpreter, and no `DT_NEEDED`. The target
smoke test runs a controlled shell process that keeps a uniquely named
temporary file descriptor open, invokes the candidate with machine-readable
fields and name resolution disabled, and requires the expected PID/file path.
Use bounded waits and clean up the child and temporary directory on every exit.
Only then replace `artifacts/<architecture>/lsof`.

## Affected Components

- `recipes/lsof/aarch64/*` and `recipes/lsof/x86_64/*`: add locked source,
  build/export scripts, procfs smoke tests, READMEs, notices, licenses, and
  final-link inventories.
- `recipes/catalog.tsv`: add enabled lsof rows for both supported architectures.
- `artifacts/aarch64/lsof` and `artifacts/x86_64/lsof`: add/replace the
  validated static executables.
- `artifacts/SHA256SUMS`: add sorted exact checksum records.
- `README.md`: list lsof 4.99.5 and architecture-specific recipe links
  concisely.
- `TRUST.md`: record the checksum-only source and both `Not verified` artifacts,
  replacing the legacy no-evidence row.

## Implementation Sequence

1. Fetch the 4.99.5 release asset to temporary storage, verify its exact hash
   and size, inspect its `COPYING`, and explicitly retain the accepted bytes
   and reviewed materials in each recipe.
2. Implement and validate one native static build with explicit libtirpc and
   link-map reconciliation; port only architecture constants to the second
   recipe.
3. Run the focused version/feature/procfs smoke test on each target architecture
   before installing either candidate; retain cache/build diagnostics for any
   late validation retry.
4. Add both catalog rows and artifacts, replace the legacy x86-64 file, update
   the sorted checksum manifest, and revise only the nearest user/trust docs.

## Validation

- Run `python3 scripts/recipes.py validate` and require two visible
  checksum-only lsof notices; run `python3 -m unittest tests.test_recipes`,
  shell syntax checks, `./build.sh list`, and `git diff --check`.
- Run `./build.sh lsof x86_64` and `./build.sh lsof aarch64` once each and
  require version 4.99.5, intended RPC/IPv6/process-task features, correct
  machine/`ET_EXEC`, no interpreter/`DT_NEEDED`, stripped output, and complete
  linked-archive evidence.
- In each target container, hold a unique file open and assert lsof returns the
  expected PID and exact path; fail if only version output succeeds.
- Run `sha256sum -c artifacts/SHA256SUMS`, inspect final sizes/modes, and confirm
  only the intended legacy x86-64 artifact was replaced.
- Confirm tcpdump assurance is not selected solely by the new lsof catalog and
  manifest rows and no attestation or utility image was added.

## Success Criteria

- Both explicit root commands rebuild lsof 4.99.5 from tracked checksum-locked
  source using the architecture's immutable builder and no ordinary-build
  network/package resolution.
- Both committed outputs are stripped static native executables that retain the
  documented Linux/libtirpc feature profile and find the controlled open file.
- Source limitation, final-link provenance, licenses, checksums, and `Not
  verified` artifact status are complete and factual for both architectures.

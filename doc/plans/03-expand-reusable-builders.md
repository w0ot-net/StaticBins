# Plan: Expand the Reusable Static Builders

*Distilled: 2026-08-07*

## Summary

Publish one new version of each architecture's reusable Alpine builder with
the static libraries and build tools required by gdbserver, lsof, socat, and
strace. Keep GHCR ownership architecture-based rather than creating an image
per utility, and adopt each new image only after it is published and its
immutable digest is committed. Prove once that the expanded environments do
not alter the existing tcpdump build or the already-recorded GDB recipe output.

## Problem

The AArch64 builder is GDB-capable but lacks static libtirpc and LibreSSL inputs.
The x86-64 builder intentionally contains only the minimal tcpdump toolchain.
The requested recipes must not run `apk add`, resolve fresh packages, or fall
back to mutable images, so lsof's RPC support, socat's TLS support, and the
gdbserver build prerequisites must exist in published digest-locked builders
before any of those recipes can be enabled.

Changing an architecture lock also changes an input to existing GDB or tcpdump
recipes. That migration must be checked once rather than assumed harmless or
rediscovered by every later tool plan.

## Scope

In scope:

- Determine and pin the smallest direct Alpine 3.24.1 package additions needed
  for both architectures to build the four selected feature profiles.
- Provide static libtirpc plus RPC headers for lsof and static LibreSSL plus its
  OpenSSL-compatible command-line tool for socat's linked and functional TLS
  checks.
- Add only the GDB-release prerequisites that an actual `all-gdbserver` build
  proves are required on x86-64; reuse the broader existing AArch64 toolchain.
- Strengthen each local builder check to require the commands and static
  archives promised to recipes.
- Bump both non-replaceable builder tags, publish them through the existing
  architecture-allowlisted workflow, and commit their public immutable
  digests.
- Before adopting the digests, build existing tcpdump and GDB candidates once
  with the new builders and check that the expansion did not change their
  established recipe outputs.
- Update the concise builder documentation and any existing notice that names
  an obsolete builder digest.

Out of scope:

- Creating or publishing utility images, tool-specific builders, a VM, or a
  third builder architecture.
- Adding the new tool recipes or source archives.
- Upgrading Alpine, compilers, existing dependency versions, GDB, or tcpdump.
  The socat recipe's separately justified 1.8.1.3 source selection does not
  change a builder input.
- Replacing the committed GDB or tcpdump artifacts. A candidate mismatch is a
  stop condition for this plan, not permission to rewrite or downgrade an
  existing artifact-trust contract.
- Refactoring the two small builder directories into shared generated code.

## Design

Retain `builders/aarch64/` and `builders/x86_64/` as the only builder owners and
the existing `ghcr.io/w0ot-net/static_bins-builder` repository. Start with the
following direct additions from the repositories fixed by the locked Alpine
base, and remove any candidate package that a real configure/link probe proves
unnecessary:

- both architectures: `libtirpc-dev`, `libtirpc-static`, `rpcsvc-proto`,
  `libressl`, `libressl-dev`, and `libressl-static`;
- x86-64: `autoconf`, `automake`, `libtool`, `pkgconf`, `expat-dev`, and
  `expat-static`, plus only any GMP/MPFR tool that GDB 16.3 actually requires
  for `all-gdbserver`. AArch64 already contains the generated-build tools.

Commit every retained direct input as an exact `name=version` row in the
architecture's `packages.lock`. The initial Alpine 3.24.1 resolution observed
libtirpc `1.3.5-r1`, rpcsvc-proto `1.4.4-r0`, LibreSSL `4.3.1-r0`, expat
`2.8.2-r0`, and pkgconf `2.5.1-r0`; implementation must re-resolve against the
unchanged locked base and fail rather than silently substitute versions.

Extend `builders/*/build.sh` validation to aggregate missing commands, package
version mismatches, and required archives in one pass. At minimum prove static
links against libtirpc, LibreSSL's `libssl.a`/`libcrypto.a`, expat where
selected, and musl/libgcc, in addition to the existing architecture and
OCI-label checks. This validates capabilities, not the utilities themselves.

Use new versioned tags (the next `*-alpine-3.24.1-rN` values) and the unchanged
manual `.github/workflows/publish-builder.yml`. Publish from the implementation
branch, capture the reported per-platform digest, anonymously pull and inspect
it, and only then update `BUILDER_IMAGE` in each `environment.lock`. There is no
mutable fallback or interval where an ordinary recipe is allowed to consume an
unpublished digest.

Before lock adoption, use the candidate images as Docker build arguments to
produce temporary outputs without installing them over committed artifacts.
The x86-64 tcpdump candidate must equal its committed attested SHA-256. The
AArch64 GDB candidate must equal the prior documented recipe result
`8e729a88937e2187a9288ae9914748ae3946285227a76ce37232802df8319f4a`, proving
the package additions did not create a second GDB result; its different
committed artifact remains explicitly `Not verified` and unchanged. Do not
repeat builds using the old images because the comparison values are already
recorded.

## Affected Components

- `builders/aarch64/packages.lock` and `builders/x86_64/packages.lock`: pin the
  minimal new direct package inputs.
- `builders/aarch64/build.sh` and `builders/x86_64/build.sh`: validate all
  promised commands, packages, static archives, and static-link probes.
- `builders/aarch64/environment.lock` and
  `builders/x86_64/environment.lock`: record new non-replaceable tags and the
  published immutable digests after publication.
- `recipes/tcpdump/x86_64/licenses/NOTICE.md`: replace the factual locked
  builder digest if it remains embedded there.
- `README.md`: list the new builder tags while retaining the publish-then-lock
  lifecycle and the external `x64-*` compatibility spelling.

## Implementation Sequence

1. Resolve exact packages against each unchanged base digest and run bounded
   configure/link probes for GDB 16.3 gdbserver, lsof 4.99.5 with libtirpc,
   socat 1.8.1.3 with LibreSSL and no readline, and strace 6.16 without optional
   unwind libraries. Remove packages not required by those profiles.
2. Update package locks and candidate validation, then build each candidate
   image and report every missing capability in one run.
3. Build temporary GDB and tcpdump outputs once with the candidates. Require
   the recorded GDB recipe-result hash and exact committed tcpdump hash before
   publication. Warn the user before the AArch64 GDB build because emulation
   may exceed ten minutes.
4. Bump versioned tags, publish each candidate through the existing native
   workflow, inspect the reported architectures/SBOM/provenance/labels, and
   verify anonymous pulls by digest.
5. Commit and push the immutable digests and bounded documentation updates.
   Require the selected post-push workflow on `main` to perform the exact
   tcpdump comparison and attestation once; reuse the candidate evidence instead
   of repeating GDB locally.

## Validation

- Run Bash syntax checks and `git diff --check` before any image build.
- Run `./builders/x86_64/build.sh` and `./builders/aarch64/build.sh`; inside
  each candidate verify `uname -m`, every direct package version, expected
  commands, required `.a` files, static probe architecture/type, no interpreter,
  and no `DT_NEEDED` entries.
- Perform one candidate build for existing tcpdump and GDB as described in the
  design, preserving their committed files and comparing hashes from temporary
  output.
- Dispatch the builder workflow once per architecture, confirm versioned-tag
  non-replacement, then anonymously pull the exact reported digests and inspect
  their OCI architecture, source label, SBOM, and provenance.
- Run `python3 scripts/recipes.py validate`, `python3 -m unittest
  tests.test_recipes`, and `./build.sh list` after lock adoption.
- Require the post-push `main` exact tcpdump job to reproduce
  `cdd8f895dceb63d428f137ed910cc083dde2bc76d1006e3468b6f8d654c053b1`.

## Success Criteria

- Both supported architectures have one published, immutable, reusable builder
  digest capable of the four requested recipe profiles without package
  resolution during ordinary builds.
- Builder validation fails clearly for a missing package, wrong version,
  missing static archive, wrong architecture, dynamic probe, or bad OCI label.
- Existing GDB and tcpdump outputs are demonstrably unaffected by the package
  expansion; their committed artifacts and assurance labels do not change.
- No per-utility GHCR image, VM, mutable builder reference, or package fallback
  is introduced.

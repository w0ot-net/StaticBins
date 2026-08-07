# Plan: Lock the x86-64 Build Environment

## Summary

Create and publish the first digest-locked x86-64 Alpine builder for the
repository. Reuse the AArch64 environment-lock and separate builder-lifecycle
contract, but include only the packages required by the first migrated
x86-64 recipe, tcpdump. This plan does not change any committed binary; it is
the independently reviewable prerequisite for rebuilding tcpdump.

## Problem

The x86-64 tcpdump script installs whatever packages the current Alpine
repositories serve at build time. There is no x86-64 base-image lock, direct
package inventory, published builder digest, or maintainer command that can
prove which dependency environment produced `x64_bins/tcpdump`. A compliant
tcpdump recipe cannot resolve those packages during a normal artifact build,
because the repository contract requires it to consume a previously published
builder by immutable digest.

## Scope

In scope:

- Add an x86-64 environment lock containing an architecture-specific Alpine
  base digest, the pinned binfmt helper, a versioned builder tag, and the final
  published builder digest.
- Record exact direct APK versions for the smallest toolchain that can build
  and validate tcpdump and its source-built libpcap dependency.
- Add a local maintainer command that builds and validates an x86-64 builder
  candidate without modifying an artifact.
- Extend the existing manual builder-publication workflow with a fixed,
  allowlisted x86-64 selection that publishes the versioned and floating tags
  and reports the immutable digest.
- Publish the candidate, commit its digest to the environment lock, and verify
  that it can be pulled anonymously.
- Update the nearest builder documentation for the new architecture.

Out of scope:

- Rebuilding `x64_bins/tcpdump` or changing its legacy build script; that is
  owned by the next ordered plan.
- Adding packages for `gdbserver`, `lsof`, `socat`, `strace`, or hypothetical
  future recipes.
- Refactoring the two architecture directories behind a new configuration
  layer or shared script library.
- Adding an interactive x86-64 builder-shell wrapper; the candidate command and
  direct container inspection are sufficient for this builder lifecycle.
- Mirroring Alpine repositories or claiming byte-for-byte reproducibility of
  the builder image.

## Design

Add `x64_alpine_build_scripts/environment.lock` with the same ownership model
as the AArch64 lock, but do not share values across architectures. Use
`linux/amd64` as the container platform, require an Alpine 3.24.1 image digest
whose image configuration is `amd64`, retain the already reviewed binfmt image
by digest, and use a distinct builder tag such as
`x64-alpine-3.24.1-r1`. `BUILDER_IMAGE` is added or finalized only after the
versioned candidate has been published and its registry digest is known.

`builder-packages.lock` contains exact `name=version` specifications for the
direct inputs actually needed to compile libpcap and tcpdump from release
archives and validate the result. It must not retain legacy dependencies such
as the distribution `libpcap-dev` package, OpenSSL development files, or CMake
when the recipe builds libpcap itself and disables those optional tcpdump
features. The published image digest remains the dependency-closure lock;
ordinary recipes never run `apk update` or `apk add`.

The x86-64 builder Dockerfile requires the locked Alpine image as a build
argument, installs the package lock, and adds the same repository-source OCI
label as the AArch64 builder. `build-builder.sh` follows the existing native-or-
Buildx behavior: it builds `linux/amd64`, validates the image architecture,
exact direct package versions, required commands, static musl archive, and OCI
label, and stops with a useful prerequisite error. It may use the locked binfmt
helper to test amd64 container execution on a non-x86-64 host, but it may not
select a mutable base or package set.

Keep `.github/workflows/publish-builder.yml` as the single owner of builder
publication. Add a `workflow_dispatch` architecture choice restricted to
`aarch64` and `x64`, map each value to a fixed directory, platform, native
runner, versioned tag, and floating tag, and reject anything else before using
paths or image names. The x64 branch runs on a native x86-64 GitHub runner,
refuses to replace an existing versioned tag, retains pinned action commits,
cache, SBOM, provenance, and OCI repository linkage, and reports the digest for
an explicit follow-up lock commit. The existing AArch64 selection must retain
its current behavior and references.

## Affected Components

- `x64_alpine_build_scripts/environment.lock`: new owner for the amd64 Alpine
  base, binfmt helper, builder version, and published builder digest.
- `x64_alpine_build_scripts/builder-packages.lock`: exact direct APK inputs for
  the minimal tcpdump-capable builder.
- `x64_alpine_build_scripts/Dockerfile`: build the reusable x86-64 toolchain
  from the required locked base and package inventory.
- `x64_alpine_build_scripts/build-builder.sh`: provide the local candidate
  build and validation entry point.
- `.github/workflows/publish-builder.yml`: add the bounded x64 publication path
  while preserving the existing AArch64 path.
- `README.md`: document the x86-64 builder maintainer command, versioned image,
  and publish-then-lock lifecycle without yet claiming tcpdump rebuild support.

## Implementation Sequence

1. Resolve the linux/amd64 digest for Alpine 3.24.1 and the exact direct APK
   versions needed by a minimal libpcap/tcpdump toolchain, then add the x64
   environment and package locks without copying unrelated AArch64 packages.
2. Add the x64 builder Dockerfile and candidate command; build it locally and
   validate its platform, commands, static libc archive, package inventory, and
   OCI label.
3. Extend the manual builder workflow through a fixed architecture selection
   and validate that its original AArch64 mapping is unchanged.
4. Commit and push the candidate definition, publish the new versioned builder
   on the native x86-64 runner, and confirm the workflow reports an amd64 image
   digest without replacing any existing versioned tag.
5. Commit the exact public digest as `BUILDER_IMAGE`, update the bounded README
   text, and anonymously pull and inspect the locked image from a clean Docker
   credential context.

## Validation

- Run `bash -n x64_alpine_build_scripts/build-builder.sh`, parse the changed
  workflow as YAML, run ShellCheck when available, and run `git diff --check`.
- Check that every image reference in the final x64 environment lock contains
  `@sha256:`, that the builder tag begins with `x64-`, and that no script has a
  mutable fallback.
- Run `./x64_alpine_build_scripts/build-builder.sh`; verify Docker reports
  architecture `amd64`, the container reports `uname -m` as `x86_64`, every
  direct package matches `builder-packages.lock`, and the required compiler,
  build, download, archive, ELF-inspection, checksum, and strip commands exist.
- Compile and statically link a minimal probe inside the candidate and use
  `file` plus `readelf` to confirm the toolchain can emit an x86-64 executable
  with no requested interpreter or `DT_NEEDED` entries.
- Dispatch the x64 builder workflow, anonymously pull both its versioned tag
  and the committed digest, and confirm they resolve to the reported amd64
  image. Inspect the SBOM, provenance, and OCI source label.
- Exercise or mechanically validate the unchanged AArch64 workflow selection
  so the shared workflow still resolves its original directory, ARM64 runner,
  platform, tags, and locked base.

## Success Criteria

- The repository contains one exact, public x86-64 builder digest whose base
  and direct package inputs are recorded and whose image is `linux/amd64`.
- Rebuilding or publishing a builder is an explicit maintainer operation; a
  future ordinary tcpdump build can consume the committed digest without APK
  resolution or a mutable fallback.
- The local candidate command and native publication workflow reject an
  incorrect architecture, package inventory, OCI label, or existing versioned
  tag.
- The existing AArch64 builder publication behavior remains intact.

## Execution Notes

Implemented the x86-64 builder lifecycle in commits `404509e` and `ab1f011`.
The architecture owns its Alpine and package locks, Dockerfile, and local
candidate command under `x64_alpine_build_scripts/`. The existing builder
workflow now accepts only the fixed `aarch64` and `x64` choices and maps them to
their repository directories, native runners, container platforms, cache
scopes, and floating tags. The README documents both candidate commands and the
publish-then-lock lifecycle. No artifact or legacy x86-64 recipe changed.

The minimal direct package investigation made one bounded correction to the
provisional five-package set: a scratch build proved that the libpcap 1.10.4
release still requires Flex and Bison. The final lock therefore contains seven
direct packages. The same scratch build also showed that libpcap rejects the
legacy `--enable-static` option; removing that unsupported option belongs to
the tcpdump recipe plan and did not change this builder outcome. Local Docker
did not provide Buildx, so candidate validation exercised the native
`docker build` fallback.

Builder workflow run `31141833649` published
`x64-alpine-3.24.1-r1` and `x64-latest` with digest
`sha256:ed0de561168a27489545d883e790707ae9a34c9412ce6e944c973bc3d848b030`.
The digest is committed in the x64 environment lock. Anonymous pulls confirmed
that the digest and both tags resolve to the same amd64 image. Inspection
confirmed the repository OCI source label, all seven exact direct package
versions, required commands, static musl archive, an SPDX SBOM attestation, and
SLSA provenance.

Validation completed successfully:

- Shell syntax, workflow YAML parsing, immutable-reference checks, and
  `git diff --check`.
- `./x64_alpine_build_scripts/build-builder.sh`, including native amd64 image,
  package, command, label, and static ELF probe checks.
- A scratch tcpdump 4.99.4/libpcap 1.10.4 build in the exact locked base,
  producing a stripped x86-64 `ET_EXEC` with no interpreter or `DT_NEEDED`
  entries and the expected version output.
- Successful native x86-64 publication run `31141833649`, versioned-tag
  non-replacement preflight, anonymous digest/tag pulls, package inspection,
  and SBOM/provenance manifest inspection.
- Mechanical verification that the shared workflow retains the original
  AArch64 directory, runner, platform, cache scope, and tags.

Deliberately excluded work remains unchanged: the tcpdump artifact migration,
the other four x86-64 binaries, an interactive x86-64 builder wrapper, shared
cross-architecture script abstractions, Alpine mirroring, and byte-for-byte
reproducibility.

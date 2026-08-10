# Build environments

This page owns reusable-builder identity, locks, publication, and platform
translation. Return to the [architecture index](../README.md).

`builders/catalog.tsv` is the machine-readable authority for the internal
identifier, Docker/OCI platform, and public builder-tag prefix in the table
below. Runtime identity and all target-specific ELF/ABI probes remain explicit
builder or recipe policy.

| Internal identifier | Docker/OCI platform | Runtime identity | Public builder prefix |
| --- | --- | --- | --- |
| `aarch64` | `linux/arm64` | `aarch64` | `aarch64-*` |
| `armv7` | `linux/arm/v7` | `armv7l` | `armv7-*` |
| `x86` | `linux/386` | Alpine `x86`; ELF `Intel 80386` | `x86-*` |
| `x86_64` | `linux/amd64` | `x86_64` | `x64-*` |

The external `x64-*` spelling is retained for public compatibility; repository
paths and catalog rows use `x86_64`.

| Internal identifier | Current immutable tag | Current recipe consumers |
| --- | --- | --- |
| `aarch64` | `aarch64-alpine-3.24.1-r4` | Baseline utility set plus bpftrace |
| `armv7` | `armv7-alpine-3.24.1-r3` | Baseline utility set |
| `x86` | `x86-alpine-3.24.1-r2` | Baseline utility set |
| `x86_64` | `x64-alpine-3.24.1-r5` | Baseline utility set plus bpftrace |

The AArch64 r4 and x86-64 r5 environments add the bpftrace static dependency
set: BCC 0.36.1, LLVM and Clang 20.1.8, libbpf, cereal, bzip2, libxml2, CMake,
Ninja, and UPX. Their candidate validation requires the exact packages and the
static archives used by the final link. UPX is a deliberate release tool for
the otherwise hosting-limit-sized bpftrace executable; recipes still validate
the unpacked link before packing and the packed executable afterward.

bpftrace is an approved architecture-limited utility for AArch64 and x86-64.
Alpine excludes its bpftrace package on x86, while the requested rollout did
not adopt the additional ARMv7 LLVM/Clang builder footprint and emulated build
cost. The enabled recipe catalog, rather than baseline readiness, expresses
that exact availability.

The x86-64 environment retains the established GDB 17.2 static dependency set:
Expat, GMP, MPFR, ncurses, xz, zlib, and zstd. Its candidate validation links
and executes one static C++ probe against that complete set before publication.

The 32-bit x86 r1 environment is the reviewed package union for the same six
utility profiles. It maps repository and Alpine identifier `x86` to OCI
`linux/386`, and its candidate proves Alpine package identity plus static ELF32
little-endian `Intel 80386` C and C++ execution under the explicit
`-march=i686 -msse2 -mfpmath=sse` baseline. Builder availability remained a
separate foundation until the architecture's utility recipes were activated.

Each `builders/<architecture>/` owns a Dockerfile, exact `packages.lock`, and
`environment.lock`. The environment lock pins the Alpine base and binfmt helper
by digest, a non-replaceable builder tag, and the exact published
`BUILDER_IMAGE` digest. Candidate commands validate package versions, promised
commands and archives, static link probes, runtime architecture, and OCI
labels. ARMv7 additionally proves ELF32, little-endian hard-float output and
the OCI `arm`/`v7` variant.

Builder publication is a maintainer operation separate from artifact builds:

1. Change package inputs and validation under a new versioned tag.
2. Validate a local candidate and any affected existing recipe output.
3. Authenticate Docker to GHCR with a GitHub token authorized to write packages
   and run `./builders/publish.sh <architecture>`.
4. Refuse replacement of an existing versioned tag; publish the new image with
   SBOM and provenance.
5. Inspect and anonymously pull the reported immutable digest.
6. Only then commit that digest to `environment.lock` for recipes to consume.

The local publisher accepts only identifiers in the builder catalog, derives
their platform and tags from the selected row, uses Docker Buildx for every
platform, and invokes the architecture's candidate validator before pushing.
When the workstation is not the target architecture, that validator registers
only the committed binfmt image and proves target execution. This affects
builder execution, not the architecture promise: every resulting recipe
artifact must run on its destination host.

For a selected architecture's first publication only, the publisher accepts
an otherwise complete environment lock before `BUILDER_IMAGE` exists. Every
normal dispatcher and repository-validation path remains strict, and the
reported immutable digest must be adopted before a recipe can be activated.

Registry authentication remains in Docker's external credential configuration.
The publisher accepts no token argument, never edits `environment.lock`, and
fails closed when registry inspection cannot prove a versioned tag is unused.

Ordinary recipes consume only the committed builder digest and install no
packages. GHCR is therefore an environment distribution surface, not a utility
distribution surface. See the [architecture-onboarding procedure](../../adding-an-architecture.md)
and [distribution model](../distribution/DISTRIBUTION_MODEL.md).

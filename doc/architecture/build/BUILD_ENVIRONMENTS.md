# Build environments

This page owns reusable-builder identity, locks, publication, and platform
translation. Return to the [architecture index](../README.md).

| Internal identifier | Docker/OCI platform | Runtime identity | Public builder prefix |
| --- | --- | --- | --- |
| `aarch64` | `linux/arm64` | `aarch64` | `aarch64-*` |
| `armv7` | `linux/arm/v7` | `armv7l` | `armv7-*` |
| `x86_64` | `linux/amd64` | `x86_64` | `x64-*` |

The external `x64-*` spelling is retained for public compatibility; repository
paths and catalog rows use `x86_64`.

| Internal identifier | Current immutable tag | Current recipe consumers |
| --- | --- | --- |
| `aarch64` | `aarch64-alpine-3.24.1-r2` | GDB, GDBserver, lsof, socat, strace, tcpdump |
| `armv7` | `armv7-alpine-3.24.1-r2` | GDB, GDBserver, lsof, socat, strace, tcpdump |
| `x86_64` | `x64-alpine-3.24.1-r3` | GDB-ready; GDBserver, lsof, socat, strace, tcpdump |

The x86-64 r3 environment adds the established GDB 17.2 static dependency set:
Expat, GMP, MPFR, ncurses, xz, zlib, and zstd. Its candidate validation links
and executes one static C++ probe against that complete set before publication.

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

The local publisher accepts only the three internal architecture identifiers,
uses Docker Buildx for every platform, and invokes the architecture's candidate
validator before pushing. When the workstation is not the target architecture,
that validator registers only the committed binfmt image and proves target
execution. This affects builder execution, not the architecture promise: every
resulting recipe artifact must run on its destination host.

Registry authentication remains in Docker's external credential configuration.
The publisher accepts no token argument, never edits `environment.lock`, and
fails closed when registry inspection cannot prove a versioned tag is unused.

Ordinary recipes consume only the committed builder digest and install no
packages. GHCR is therefore an environment distribution surface, not a utility
distribution surface. See the [distribution model](../distribution/DISTRIBUTION_MODEL.md).

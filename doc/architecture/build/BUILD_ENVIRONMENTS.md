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
3. Push the candidate definition and manually run the architecture-allowlisted
   publication workflow.
4. Refuse replacement of an existing versioned tag; publish the new image with
   SBOM and provenance.
5. Inspect and anonymously pull the reported digest.
6. Only then commit that digest to `environment.lock` for recipes to consume.

Publication uses a native hosted runner where one exists. The ARMv7 builder
runs on the ARM64 host with the committed binfmt digest because no hosted
ARM32 runner exists. This affects builder execution, not the architecture
promise: every resulting recipe artifact must run on its destination host.

Ordinary recipes consume only the committed builder digest and install no
packages. GHCR is therefore an environment distribution surface, not a utility
distribution surface. See the [distribution model](../distribution/DISTRIBUTION_MODEL.md).

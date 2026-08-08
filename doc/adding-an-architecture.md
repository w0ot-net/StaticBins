# Adding an architecture

A supported architecture starts with a published, locked builder. Adding its
catalog row does not create tool coverage: each utility still needs a complete
recipe, committed artifact, target checks, checksum, and trust record.

## 1. Define the target

Choose one safe lowercase internal identifier and specify the actual Linux host
ABI: machine, ELF class, endianness, executable type, and any ABI flags such as
ARM hard-float. Identify the Docker/OCI platform and a unique lowercase public
builder-tag prefix ending in `-`. Record stable target-specific rules in the
nearest architecture page; do not place ELF strings or binfmt names in the
generic catalog.

Add one sorted row to `builders/catalog.tsv`:

```text
architecture	platform	tag_prefix
<architecture>	linux/<arch>[/<variant>]	<prefix>-
```

## 2. Add the builder owner

Create `builders/<architecture>/` with:

```text
Dockerfile
packages.lock
environment.lock
build.sh
```

Pin the Alpine base and binfmt helper by digest, lock exact package versions,
choose a new non-replaceable `BUILDER_TAG` beginning with the catalog prefix,
and leave `BUILDER_IMAGE` absent only until the first publication supplies its
digest. The executable candidate command must use Docker Buildx and fail closed
while checking exact packages, required commands and static archives, target
runtime identity, the promised static ELF/ABI, and OCI labels. Add
architecture-specific probes; do not weaken them into generic
lowest-common-denominator checks.

Run the fast contract checks and the real candidate validation:

```sh
./validate.sh
./builders/<architecture>/build.sh
```

## 3. Publish and adopt the builder

Authenticate Docker to GHCR outside the repository, then publish once:

```sh
docker login ghcr.io -u w0ot-net
./builders/publish.sh <architecture>
```

The publisher refuses an existing versioned tag and pushes the versioned and
architecture-floating tags with SBOM and provenance. Inspect the reported
image anonymously: require the intended platform, source label, target runtime,
attached attestations, and exact digest. Only then commit the reported immutable
`BUILDER_IMAGE` to `builders/<architecture>/environment.lock`. The publisher is
the only catalog consumer that accepts this selected prepublication owner
without `BUILDER_IMAGE`; normal dispatch and repository validation reject it.
Builder publication and digest adoption are a separate maintainer change from
recipes.

## 4. Activate utilities

Follow [`adding-a-binary.md`](adding-a-binary.md) for each tool. A recipe must
consume the committed builder digest, use tracked checksum-locked source, prove
the precise target ELF/ABI and static link, run a target-architecture functional
smoke test, and install only its validated candidate at
`artifacts/<architecture>/<tool>`.

Add its sorted `recipes/catalog.tsv` row only with the complete recipe and
artifact change. Update `artifacts/SHA256SUMS`, `TRUST.md`, and the owning
ABI/build documentation. Current availability is discovered from the enabled
catalog and committed artifact set, not a separately maintained user-facing
index. Finish with the direct recipe build and `./validate.sh`; do not rebuild
unrelated architectures.

The published builder remains a builder-only foundation during this rollout.
Present the architecture as ready for utility users only after it has an
enabled recipe and committed artifact for every tool already distributed on
the repository's ready architectures. This permits builder-first onboarding
without silently advertising partial utility coverage.

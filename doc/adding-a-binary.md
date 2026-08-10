# Adding a static binary

A reproducible binary is one conventional tool recipe plus one three-field row
in `recipes/catalog.tsv`. Tool-specific source, configuration, build, license,
and smoke-test logic stays inside the recipe; the root dispatcher and local
repository validation remain generic.

A newly distributed utility should have a complete recipe and artifact for
every ready architecture. If that rollout is still incomplete, keep all of its
pairs out of the enabled catalog and public artifact set until the remaining
architecture owners are ready. An explicitly approved architecture-limited
utility is the narrow exception: document every omitted ready architecture and
its compatibility or scope reason in each recipe README, and rely on the
catalog as the exact availability authority. Such an exception does not
redefine an architecture's baseline readiness.

This procedure implements the repository's stable
[repository model](architecture/repository/REPOSITORY_MODEL.md),
[build pipeline](architecture/build/BUILD_PIPELINE.md),
[artifact contract](architecture/artifacts/ARTIFACT_CONTRACT.md), and
[trust chain](architecture/trust/TRUST_CHAIN.md).

## Required layout

For a tool named `<tool>` on `<architecture>`, add:

```text
artifacts/<architecture>/<tool>
builders/<architecture>/environment.lock
recipes/<tool>/<architecture>/
  Dockerfile
  build.sh
  build-in-container.sh
  source.lock
  sources/
    <checksum-locked upstream archives>
    <detached signatures and minimal keyrings when authentication is pgp>
  licenses/
    NOTICE.md
    archive-inventory.tsv
    ...reviewed license texts...
```

The internal architecture name must have a valid row in
[`builders/catalog.tsv`](../builders/catalog.tsv). OCI platform translation is
owned at that builder boundary; target ELF, ABI, and runtime checks remain
explicit in the architecture-specific recipe.

The architecture must already have a locked, published builder. The recipe's
host `build.sh` and committed output must be executable. The host command must
be non-interactive, validate a temporary candidate completely before replacing
the committed artifact, and enforce the target architecture and static-ELF
contract. It must fail before build setup when Docker Buildx is unavailable and
must use its Dockerfile through one unconditional Buildx path; do not select a
direct-container or classic Docker fallback.

Select one release profile: classic static `ET_EXEC` or static PIE `ET_DYN`.
Both reject `PT_INTERP` and `DT_NEEDED`; static PIE additionally requires a
nonzero entry point, an executable `PT_LOAD`, `DF_1_PIE`, and no text
relocations. Do not use `-no-pie` as evidence of static linkage. A new recipe,
or an existing recipe whose final-link policy is under review, may explicitly
force non-PIE output only with a concrete compatibility or toolchain reason in
its README. Existing validated artifacts need not be relinked solely to change
profile.

`source.lock` owns the source
version, archive, checksum, official provenance URL, license identifier, and
explicit authentication mode. The corresponding regular, non-symlink archive
must be committed with mode `100644` at `sources/<archive>` and its actual bytes
must match the lock before extraction.

Set `<PREFIX>_AUTHENTICATION` to `pgp` or `checksum-only` for every bounded
source record. A `pgp` record also requires safe filenames in
`<PREFIX>_SIGNATURE` and `<PREFIX>_SIGNING_KEY`, plus the exact 40-character
uppercase fingerprint in `<PREFIX>_SIGNER_FINGERPRINT`. Commit both evidence
files as regular mode-`100644` files under `sources/`; use a minimal keyring
containing the required signer. A `checksum-only` record must not retain PGP
fields. It is accepted but visibly weaker, never a fallback after a signature
failure. See [`TRUST.md`](../TRUST.md) for the assurance model.

If a tool requires another source archive, keep that dependency in the same
tool-owned lock and `sources/` directory. Add another complete uppercase
`<PREFIX>` record with the same base fields as `SOURCE_`; generic repository
validation discovers and verifies it without tool-specific changes. Keep
dependency-specific configuration inside the recipe; the catalog is not a
general dependency resolver. Source updates are reviewed repository changes:
download from the recorded official HTTPS URL into temporary storage, verify
the checksum and size, and explicitly stage the archive. Do not create
source-only releases for recipe inputs.

## Catalog row

Add one tab-delimited row to `recipes/catalog.tsv`:

| Field | Contract |
| --- | --- |
| `name` | Lowercase tool identifier and artifact filename; unique with architecture |
| `architecture` | Supported identifier from `builders/catalog.tsv` |
| `enabled` | `true` to list and build; otherwise `false` |

Do not quote fields or place commands, workflow expressions, tabs, or newlines
inside values. Every other value is derived and validated:

- recipe: `recipes/<name>/<architecture>/`
- output: `artifacts/<architecture>/<name>`
- builder lock: `builders/<architecture>/environment.lock`
- source version and checksums: validated from the recipe's `source.lock`

Disabled rows must still be complete and valid; they are omitted from user
dispatch but remain subject to repository validation.

## Validate and build

Run the fast checks first:

```sh
./validate.sh
```

The command composes catalog/source/artifact validation, focused unit tests,
dispatcher listing, and tracked shell syntax checks. It requires `gpgv` and
checks all declared PGP records offline using only their committed evidence.

Then build and test the selected recipe through the stable public command:

```sh
./build.sh <tool> <architecture>
```

The architecture may be omitted only while exactly one catalog row has that
tool name. Multi-architecture tools always require the explicit form.

Verify the resulting architecture, static linkage, version behavior, and the
tool's focused functional smoke test on its target architecture, either
natively or through the recipe's supported QEMU path. Commit the validated
executable under `artifacts/<architecture>/<tool>`. Local validation does not
build or publish a utility image. GHCR publication is reserved for the
separately maintained reusable builders.

Update `artifacts/SHA256SUMS` with exactly one sorted, repository-relative
SHA-256 record for the new executable. Repository validation requires that set
of paths to match the catalog's conventional outputs. The common source and
recipe-validation statements in `TRUST.md` apply automatically; update its
exception table only when the artifact has independent exact-rebuild or
attestation evidence, or when a common trust statement itself changes. A source
signature or checksum still does not identify who built the artifact.

Run `./validate.sh` again after updating the catalog, artifact manifest, and
any required TRUST evidence. Commit and push only after both it and the direct
recipe build succeed.

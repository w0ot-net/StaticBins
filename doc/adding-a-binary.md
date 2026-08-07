# Adding a static binary

A reproducible binary is one conventional tool recipe plus one three-field row
in `recipes/catalog.tsv`. Tool-specific source, configuration, build, license,
and smoke-test logic stays inside the recipe; the root dispatcher and recipe
validation workflow remain generic.

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

Internal architecture names are `aarch64`, `armv7`, and `x86_64`. Recipe host
commands map them to `linux/arm64`, `linux/arm/v7`, and `linux/amd64`,
respectively, when exporting local binaries.

The architecture must already have a locked, published builder. The recipe's
host `build.sh` and committed output must be executable. The host command must
be non-interactive, validate a temporary candidate completely before replacing
the committed artifact, and enforce the target architecture and static-ELF
contract. It must fail before build setup when Docker Buildx is unavailable and
must use its Dockerfile through one unconditional Buildx path; do not select a
direct-container or classic Docker fallback. `source.lock` owns the source
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
tool-owned lock and `sources/` directory. Extend catalog validation only for
that bounded lock shape, verify every archive independently, and keep
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
| `architecture` | `aarch64`, `armv7`, or `x86_64` |
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
python3 scripts/recipes.py validate
python3 -m unittest tests.test_recipes
./build.sh list
```

The validator requires `gpgv` and checks all declared PGP records offline using
only their committed evidence.

Then build and test the selected recipe through the stable public command:

```sh
./build.sh <tool> <architecture>
```

The architecture may be omitted only while exactly one catalog row has that
tool name. Multi-architecture tools always require the explicit form.

Verify the resulting architecture, static linkage, version behavior, and the
tool's focused functional smoke test. Commit the validated executable under
`artifacts/<architecture>/<tool>`. A relevant push runs fast recipe validation;
it does not build or publish a utility image. GHCR publication is reserved for
the separately maintained reusable builders.

Update `artifacts/SHA256SUMS` with exactly one sorted, repository-relative
SHA-256 record for the new executable, then record one of the two allowed
artifact statuses in `TRUST.md`: `Exact rebuild + GitHub attestation` or `Not
verified`. A source-authenticated, statically validated, or checksum-listed file
does not automatically qualify for build provenance.

Use `Exact rebuild + GitHub attestation` only after one clean native build has
passed the full recipe checks and reproduced the committed bytes exactly. Add
the tool explicitly to `.github/workflows/verify-artifacts.yml` so a selected
job rebuilds, compares, and attests the same file. A mismatch is evidence for
`Not verified`; do not hide it with a retry or silently replace artifact bytes.
Future catalog rows remain unverified until this bounded qualification and
workflow change are reviewed.

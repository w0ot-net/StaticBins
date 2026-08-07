# Adding a static binary

A reproducible binary is one conventional tool recipe plus one three-field row
in `recipes/catalog.tsv`. Tool-specific source, configuration, build, license,
and smoke-test logic stays inside the recipe; the root dispatcher and recipe
validation workflow remain generic.

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
  licenses/
    NOTICE.md
    archive-inventory.tsv
    ...reviewed license texts...
```

Internal architecture names are `aarch64` and `x86_64`. Recipe host commands
map them to the corresponding Buildx platforms when exporting local binaries.

The architecture must already have a locked, published builder. The recipe's
host `build.sh` and committed output must be executable. The host command must
be non-interactive, validate a temporary candidate completely before replacing
the committed artifact, and enforce the target architecture and static-ELF
contract. It must fail before build setup when Docker Buildx is unavailable and
must use its Dockerfile through one unconditional Buildx path; do not select a
direct-container or classic Docker fallback. `source.lock` owns the source
version, archive, checksum, official provenance URL, and license identifier.
The corresponding regular, non-symlink archive must be committed with mode
`100644` at `sources/<archive>` and its actual bytes must match the lock before
extraction.

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
| `name` | Globally unique lowercase recipe identifier and artifact filename |
| `architecture` | `aarch64` or `x86_64` |
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

Then build and test the selected recipe through the stable public command:

```sh
./build.sh <tool>
```

Verify the resulting architecture, static linkage, version behavior, and the
tool's focused functional smoke test. Commit the validated executable under
`artifacts/<architecture>/<tool>`. A relevant push runs fast recipe validation;
it does not build or publish a utility image. GHCR publication is reserved for
the separately maintained reusable builders.

# Adding a static binary

A publishable binary is one tool-owned recipe plus one row in `recipes.tsv`.
Tool-specific source, configuration, build, license, and smoke-test logic stays
inside the recipe; the root dispatcher and container workflow remain generic.

## Required layout

For a tool named `<tool>` on `<architecture>`, add:

```text
<architecture>_bins/<tool>
<architecture>_alpine_build_scripts/environment.lock
<architecture>_alpine_build_scripts/<tool>/
  Dockerfile
  build.sh
  build-in-container.sh
  source.lock
  licenses/
    NOTICE.md
    archive-inventory.tsv
    ...reviewed license texts...
```

The architecture must already have a locked, published builder. The host
`build.sh` must be executable, accept no required interactive input, write the
expected committed binary, and enforce the repository's static-ELF and target
architecture checks. `source.lock` owns source version, archive, checksum,
official URL, immutable mirror URL, and license identifier.

## Catalog row

Add one tab-delimited row to `recipes.tsv`. Do not quote fields or place shell
commands, workflow expressions, tabs, or newlines in values.

| Field | Contract |
| --- | --- |
| `name` | Stable lowercase recipe identifier and binary filename |
| `architecture` | Allowlisted architecture (`aarch64` or `x64`) |
| `version` | Must match `SOURCE_VERSION` in the recipe lock |
| `recipe_dir` | `<architecture>_alpine_build_scripts/<name>` |
| `build_script` | `<recipe_dir>/build.sh` |
| `output` | `<architecture>_bins/<name>` |
| `image` | Repository-owned GHCR image with a `static_bins-*` name |
| `tags` | `<version>-<architecture>;<architecture>-latest` |
| `cache_scope` | `<architecture>-<name>` |
| `runner` | Allowlisted native GitHub runner for the architecture |
| `enabled` | `true` to list, build, and publish; otherwise `false` |

The validator checks normalized paths, Git executable modes, required locks and
distribution files, builder digests, source metadata, runner/platform mapping,
and global name/tag/cache collisions. Disabled rows must still be complete and
valid; they are excluded from user dispatch and the publication matrix.

## Validate and publish

Run the fast checks first:

```sh
python3 scripts/recipes.py validate
python3 -m unittest tests.test_recipes
./build.sh list
```

Then build and test the selected recipe through its public entry point:

```sh
./build.sh <tool>
```

Verify the resulting architecture, static linkage, version behavior, and the
tool's focused functional smoke test. Once the recipe and binary are committed,
a push that changes the catalog, validator, workflow, architecture environment,
or recipe tree generates the enabled matrix and publishes its versioned and
floating GHCR tags with cache, SBOM, provenance, and repository OCI labels.

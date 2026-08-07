# Plan: Manifest-Driven Static Binary Recipes

## Summary

Define one small recipe catalog that drives both a root one-command build
dispatcher and the GHCR artifact matrix. Migrate the existing GDB recipe to that
contract so a future tool needs a tool-owned recipe directory plus one catalog
entry, without editing workflow YAML or duplicating shared orchestration.

This plan assumes the locked builder and per-tool source-lock contract from
`01-lock-and-mirror-build-inputs.md` is complete.

## Problem

The current publication workflow names GDB, its image, tags, context, build
arguments, and cache scope directly. `README.md` also exposes only the deep GDB
script path. Although the reusable builder can compile other C/C++ projects,
each addition would require bespoke workflow edits and there is no machine-
checked definition of what constitutes a complete recipe. Generalizing the
tool-specific compilation itself would be counterproductive because configure
flags, source layouts, licenses, and functional smoke tests vary by project.

## Scope

In scope:

- Add an explicit catalog for publishable static-binary recipes, initially
  containing the existing AArch64 GDB recipe.
- Validate catalog values, uniqueness, safe repository-relative paths, required
  recipe files, lock metadata, output location, image names, and tags without
  third-party Python packages.
- Add a root command that lists recipes and dispatches a selected recipe's
  existing host build script while preserving its environment and exit status.
- Generate a GitHub Actions matrix from the validated catalog and publish every
  enabled recipe using the locked builder, native architecture runner, standard
  cache/SBOM/provenance settings, and repository-linking OCI metadata.
- Document the bounded recipe contract and onboarding steps for future tools.
- Preserve the documented GDB-specific build command as a supported direct
  entry point.

Out of scope:

- Abstracting tool-specific download, configure, compile, strip, license, or
  functional-test logic into a plugin framework.
- A recipe generator/scaffolding command; the initial catalog and documentation
  are sufficient to make the contract explicit.
- Adding a second binary solely as a demonstration, migrating legacy x86-64
  artifacts, or adding multi-architecture/multi-runner support.
- Selective changed-recipe detection; relevant pushes may rebuild all enabled
  recipes until catalog size makes that optimization necessary.
- Byte-for-byte reproducibility, release promotion channels, signing policy, or
  package retention automation.

## Design

Add a versioned `recipes.json` whose entries contain only shared orchestration
data: stable recipe name, architecture, version, recipe directory, host build
script, expected committed output, GHCR image, immutable/versioned tags,
floating tags, cache scope, runner label, and enabled state. Source URLs,
checksums, licenses, builder digests, configure flags, and smoke-test commands
remain in their existing owners (`source.lock`, environment lock, Dockerfile,
and tool scripts) rather than being duplicated in the catalog.

Use one standard-library-only `scripts/recipes.py` as the catalog owner. Its
subcommands should:

- validate schema version, allowed fields and architecture values, unique names,
  image/tag collisions, normalized paths contained within the repository, and
  the required `Dockerfile`, `source.lock`, executable host/guest scripts, and
  expected `<architecture>_bins/` output;
- list enabled recipe names for humans;
- resolve one recipe's host command for the root dispatcher; and
- emit compact, deterministic JSON suitable for a GitHub Actions matrix,
  including preformatted tag lines but no arbitrary expressions or shell code.

The root `build.sh` accepts `list` or exactly one recipe name. It asks
`recipes.py` for a validated repository-relative build script, then executes
that script with the caller's environment and rejects extra arguments. It does
not interpret tool settings or reimplement Docker, QEMU, output, or ELF
validation; those remain with the recipe. The existing
`aarch64_alpine_build_scripts/gdb/build.sh` path remains callable because it is
already the documented artifact contract.

Refactor `.github/workflows/publish-containers.yml` into a catalog job and an
artifact matrix job. The catalog job checks out the exact commit, runs
`recipes.py validate`, and exposes `recipes.py matrix` through a job output. The
matrix job uses GitHub's documented
[job-output matrix pattern](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations#using-an-output-to-define-two-matrices)
with `fromJSON`, checks out the same commit, selects the cataloged native runner,
logs in to GHCR, and passes the locked builder digest and standard `BUILD_JOBS`
argument to each recipe Dockerfile. Image tags, cache scopes, SBOM, provenance,
and OCI source annotations remain centrally enforced by the workflow. A recipe
cannot inject action syntax or arbitrary build arguments through the catalog.

## Affected Components

- `recipes.json`: new explicit catalog and shared publication/build metadata for
  enabled recipes.
- `scripts/recipes.py`: new validator, query command, and deterministic matrix
  emitter using only the Python standard library.
- `build.sh`: new root list/dispatch command for the stable one-click user entry
  point.
- `tests/test_recipes.py`: focused coverage for valid catalogs, duplicate
  names/tags, unknown fields, unsafe/missing paths, incomplete recipes, and
  deterministic matrix output.
- `.github/workflows/publish-containers.yml`: replace GDB-specific publication
  fields with catalog validation and an artifact matrix that retains locked
  builders, native ARM64, pinned action SHAs, caching, SBOM, and provenance.
- `aarch64_alpine_build_scripts/gdb/*`: bounded migration to the standard recipe
  filenames/arguments if validation identifies a mismatch; compilation logic
  remains tool-owned.
- `README.md`: promote `./build.sh list` and `./build.sh gdb`, retain the direct
  GDB command, and link to the onboarding contract without expanding the main
  README into a manual.
- `doc/adding-a-binary.md`: new concise contract covering layout, locks, custom
  build responsibilities, catalog fields, validation, artifact placement, and
  GHCR behavior.
- `AGENTS.md`: require a validated catalog entry for publishable recipes and
  direct agents to the onboarding contract.

## Implementation Sequence

1. Define the smallest catalog schema from the existing GDB recipe and locked
   input contracts; add a GDB entry without changing its compilation behavior.
2. Implement `scripts/recipes.py` validation and matrix/query output, followed
   by focused unit tests for malformed state and deterministic output.
3. Add the root dispatcher and verify both root and existing direct GDB commands
   resolve to the same script and propagate environment overrides/failures
   unchanged.
4. Refactor the container workflow into catalog and matrix jobs, keeping all
   security-sensitive behavior in YAML and exposing only bounded data from the
   catalog.
5. Add the onboarding document and make the minimal README/AGENTS contract
   updates.
6. Run local catalog/dispatcher validation and the real publication workflow;
   inspect the resulting GDB package before declaring the migration complete.

## Validation

- Run `python3 -m unittest tests.test_recipes`, `python3 scripts/recipes.py
  validate`, and compare two `matrix` invocations for identical compact JSON.
- Run `python3 scripts/recipes.py list` and `./build.sh list`; both must list
  exactly the enabled GDB recipe.
- Use negative fixtures to prove duplicate names/tags, unknown keys, path
  traversal, missing/non-executable scripts, missing source locks, and outputs
  outside `aarch64_bins/` fail with actionable messages.
- Run `bash -n build.sh`, syntax-check existing recipe scripts, parse workflow
  YAML, and run `git diff --check`.
- Confirm the root dispatcher rejects missing, unknown, and extra recipe
  arguments; use a controlled failing fixture to verify exit-status propagation,
  then perform one full GDB build through the root path for end-to-end proof.
- Validate the rebuilt binary with `file`, `readelf`, version output, and the
  focused GDB-remote smoke test.
- Trigger the publication workflow, confirm the catalog and matrix jobs succeed,
  anonymously pull both GDB tags, inspect their OCI source/version/license
  metadata, and run `gdb --batch --version`.

## Success Criteria

- `./build.sh gdb` is a stable one-command rebuild and the existing direct GDB
  script remains functional.
- GDB publication contains no GDB-specific image, tag, context, or cache values
  in workflow logic; those values come from a validated catalog entry.
- Adding a conforming future recipe requires its tool-owned directory, expected
  committed binary, source lock, and one `recipes.json` entry, with no workflow
  edit.
- Invalid or colliding recipe metadata fails before any container build or
  publication starts.
- The public GDB package remains linked to the repository and retains versioned
  and floating tags, SBOM, provenance, static-ELF validation, and functional
  smoke coverage.

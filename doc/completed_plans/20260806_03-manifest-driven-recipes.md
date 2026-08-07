# Plan: Manifest-Driven Static Binary Recipes

*Distilled: 2026-08-06*

## Summary

Define one small line-oriented recipe catalog that drives both a Bash root build
dispatcher and the GHCR artifact matrix. Migrate GDB to that contract so a
future tool needs a tool-owned recipe directory plus one catalog row, without
editing workflow YAML or adding a Python prerequisite to the user build path.

This plan assumes `01-lock-build-environment.md` and
`02-mirror-source-inputs.md` are complete.

## Problem

The current publication workflow names GDB, its image, tags, context, build
arguments, and cache scope directly. The README exposes only the deep GDB script
path, and there is no machine-checked definition of a complete publishable
recipe. Tool-specific download, configure, license, and functional-test logic
must remain custom, but shared dispatch and publication metadata should not be
copied into every future workflow.

## Scope

In scope:

- Add an explicit catalog for publishable static-binary recipes, initially GDB.
- Validate catalog values, uniqueness, safe paths, required files, source locks,
  expected outputs, image names, and tags using only the Python standard library.
- Add a Bash root command that lists recipes and dispatches a selected recipe's
  existing host script without requiring host Python.
- Generate a GitHub Actions matrix from the same validated catalog and publish
  enabled recipes with locked builders, native runners, cache, SBOM, provenance,
  and repository-linking OCI metadata.
- Document the bounded onboarding contract while preserving the direct GDB
  command as an existing supported entry point.

Out of scope:

- Abstracting tool-specific fetch, configure, compile, strip, license, or smoke
  logic into a plugin framework.
- Adding a recipe generator or a second binary solely as a demonstration.
- Migrating legacy x86-64 artifacts or supporting additional architectures and
  runners.
- Selective changed-recipe detection, signing/retention policy, or byte-for-byte
  reproducibility.

## Design

Use `recipes.tsv` with one header and one tab-delimited row per recipe. Fields
contain no tabs, newlines, shell fragments, or workflow expressions. The bounded
schema contains stable name, architecture, version, recipe directory, host build
script, expected committed output, GHCR image, semicolon-delimited versioned and
floating tags, cache scope, allowlisted runner label, and enabled state. Source,
license, configure, builder, and smoke-test values remain in their current
owners rather than being duplicated.

The root `build.sh` validates a recipe name as a simple identifier, reads the
bounded TSV columns with Bash, requires exactly one matching enabled row,
rejects disabled or duplicate matches, confirms the host-script path is
normalized and remains inside the repository, and executes exactly that
existing script. It supports `list` or one enabled recipe name, rejects extra
arguments, preserves environment overrides and exit status, and does not
reimplement Docker/QEMU/artifact logic. The existing GDB script remains directly
callable.

Add one standard-library-only `scripts/recipes.py` for strict catalog validation
and deterministic matrix emission. It rejects an unknown schema/header,
malformed booleans/lists, unknown architectures/runners, duplicate names or
image tags, unsafe/non-normalized paths, missing/non-executable recipe scripts,
missing Dockerfile/source lock, and output paths outside the matching
`<architecture>_bins/` directory. For tracked files, executable validation reads
the Git index mode instead of trusting host filesystem modes (this workspace's
shared filesystem reports all files as executable); untracked fixture files use
their real mode. Its `matrix` command emits compact JSON with preformatted tag
lines and no arbitrary build arguments or expressions.

Refactor `.github/workflows/publish-containers.yml` into a catalog job and a
matrix job using GitHub's documented
[job-output matrix pattern](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations#using-an-output-to-define-two-matrices).
The first job validates and emits the matrix from the checked-out commit. Each
matrix job checks out that same commit, uses the allowlisted native runner,
loads the committed builder digest, logs in to GHCR, and applies centrally owned
cache/SBOM/provenance/OCI settings. Catalog data cannot choose actions, secrets,
arbitrary commands, or arbitrary Docker build arguments.
The workflow path filter includes the catalog, validator, workflow, environment
lock, and bounded AArch64 recipe tree so a metadata-only catalog change cannot
skip validation/publication.

## Affected Components

- `recipes.tsv`: new shared catalog for user dispatch and artifact publication.
- `build.sh`: new Bash-only root list/dispatch entry point.
- `scripts/recipes.py`: new strict validator and deterministic matrix emitter.
- `tests/test_recipes.py`: focused valid/invalid catalog and matrix coverage.
- `.github/workflows/publish-containers.yml`: replace GDB-specific values with
  catalog validation and a bounded artifact matrix.
- `aarch64_alpine_build_scripts/gdb/*`: only bounded naming/argument changes
  needed to conform to the catalog contract; compilation remains tool-owned.
- `README.md`: promote root list/build commands, retain the direct GDB command,
  and link the onboarding document.
- `doc/adding-a-binary.md`: new concise layout, lock, script, catalog, artifact,
  validation, and GHCR onboarding contract.
- `AGENTS.md`: require a valid catalog row for every publishable recipe and
  point to the onboarding contract.

## Implementation Sequence

1. Define the exact TSV header from the current GDB recipe and add its row
   without changing compilation behavior.
2. Implement `scripts/recipes.py` and focused unit tests for valid state,
   malformed/colliding state, safe paths, and deterministic matrix output.
3. Add the Bash root dispatcher and verify it resolves the GDB row to the
   existing script while preserving environment and failures.
4. Refactor publication into catalog and matrix jobs, leaving all
   security-sensitive behavior in workflow YAML and updating trigger paths for
   the catalog, validator, environment lock, and recipe tree.
5. Add the onboarding document and make the minimal README/AGENTS updates.
6. Run local catalog/dispatcher validation and the real publication workflow,
   then inspect and execute the resulting public GDB image.

## Validation

- Run `python3 -m unittest tests.test_recipes`,
  `python3 scripts/recipes.py validate`, and compare two `matrix` invocations
  for identical compact JSON.
- Run `./build.sh list`; it must list exactly enabled GDB. Confirm missing,
  unknown, unsafe, and extra arguments fail before executing a recipe.
- Use negative fixtures for duplicate names/tags, unknown headers, path
  traversal, missing/non-executable scripts, missing source locks, invalid
  runners, disabled dispatch, and outputs outside `aarch64_bins/`; cover tracked
  executable modes through a temporary Git index rather than `os.access` alone.
- Run `bash -n build.sh`, syntax-check existing recipe scripts, parse workflow
  YAML, and run `git diff --check`.
- Use a controlled failing fixture to verify dispatcher exit-status propagation,
  then perform one full GDB build through `./build.sh gdb`.
- Validate the resulting binary with `file`, `readelf`, version output, and the
  focused GDB-remote smoke test.
- Trigger artifact publication, confirm catalog and matrix jobs succeed, then
  anonymously pull both GDB tags and inspect/run their metadata and version.

## Success Criteria

- `./build.sh gdb` is a Bash-and-Docker one-command rebuild and the existing
  direct GDB command remains functional.
- GDB-specific image, tag, context, runner, and cache values no longer appear in
  workflow logic; they come from a validated catalog row.
- Adding a conforming future recipe requires its tool-owned directory, source
  lock, expected committed binary, and one catalog row, with no workflow edit.
- Invalid or colliding catalog state fails before any container build or
  publication starts.
- The public GDB package retains repository linkage, versioned/floating tags,
  SBOM, provenance, static-ELF checks, and functional smoke coverage.

## Execution Notes

Implemented the manifest-driven recipe contract in commit `6e30fc8`.
`recipes.tsv` contains one enabled GDB row; `build.sh` provides Bash-only list
and dispatch behavior; and `scripts/recipes.py` validates the bounded schema and
emits deterministic compact JSON for GitHub Actions. Architecture configuration
is allowlisted in the validator, while source, builder, license, configure, and
functional behavior remain owned by the recipe.

The publication workflow now has a fast catalog gate followed by a matrix job.
Catalog values can select only validated contexts, Dockerfiles, platforms,
native runners, images, tags, and cache scopes. Builder arguments, credentials,
actions, cache policy, SBOM, provenance, and repository OCI labels remain in
workflow logic. No GDB-specific image, context, runner, tag, or cache value
remains in the workflow.

Validation completed successfully:

- `python3 -m unittest tests.test_recipes` passed 11 focused tests covering
  deterministic output, unknown headers, duplicate names/full image tags,
  traversal/wrong outputs, missing required files, Git-index executable modes,
  runner allowlisting, malformed booleans/tag lists, disabled rows, dispatcher
  rejection, environment preservation, and exit-status propagation.
- `python3 scripts/recipes.py validate`, repeated identical `matrix` output,
  `./build.sh list`, Bash syntax, workflow YAML parsing, generic-workflow
  searches, and `git diff --check` passed. ShellCheck was not installed on the
  execution host.
- Catalog-driven publication run `31143090093` passed its catalog job and
  generated exactly one `gdb (aarch64)` matrix job. BuildKit reused the validated
  recipe layer, so the native job finished in 27 seconds rather than recompiling
  GDB.
- Both anonymous public tags resolve to OCI index digest
  `sha256:39276132d4b60e2ec51ec94851bb32e1830b4a9b8bf1224da88d0646d7071cc9`,
  retain an attestation manifest, carry source/version/revision OCI labels, and
  run GDB 17.2. The extracted payload is byte-identical to the committed binary
  at SHA-256
  `8e729a88937e2187a9288ae9914748ae3946285227a76ce37232802df8319f4a`.

The explicit local `./build.sh gdb` recompilation was not repeated under slow
QEMU: the unchanged direct recipe had already passed Plan 2's full native build,
static checks, and focused remote-debugging test; the root dispatch boundary was
separately proven with controlled fixtures; and the catalog-driven native
publication reused and republished those exact payload bytes. This follows the
repository's validation-efficiency rule without weakening coverage.

# Plan: Remove Utility Image Publication

## Summary

Make committed files under `artifacts/` the only distributed utility binaries
and reserve GHCR for reusable builder environments. Remove the generic utility
image publisher and its matrix metadata, retain the three-field catalog as the
build allowlist, and replace publication CI with fast repository validation.
Docker remains the recipe execution mechanism, but recipe output is exported as
a local binary rather than tagged, loaded, or pushed as a utility image.

Execute this plan only after the currently queued source-input and Buildx plans
are completed or explicitly abandoned; do not race their changes to recipes,
source locks, the validator, or documentation.

## Problem

`.github/workflows/publish-containers.yml` currently rebuilds every enabled
recipe and publishes a separate GHCR package per utility. The catalog validator
therefore derives image names, tags, cache scopes, runners, platforms, and a CI
matrix even though users consume the committed executables, not the images.
Both recipe Dockerfiles also end in runtime-image packaging stages with OCI
labels, copied notices, and executable entrypoints.

This policy has already produced public `static_bins-gdb` and
`static_bins-tcpdump` packages and repeated native builds for path or metadata
changes. It also spreads utility-image terminology through the README,
onboarding guide, agent contract, recipe documentation, notices, tests, and
active planning assumptions. None of that is needed to preserve the supported
`./build.sh <tool>` interface or the pinned builder environments.

## Scope

In scope:

- Retire utility-image publication without changing the root dispatcher,
  catalog schema, recipe source/build policy, or artifact paths.
- Rename the utility publication workflow to a fast validation workflow and
  remove all registry login, package-write permission, native build matrix,
  image tag, cache export, SBOM, provenance, and push behavior from it.
- Simplify `scripts/recipes.py` and its tests to validate repository recipes
  only; remove utility-image and matrix state that no live caller consumes.
- Keep each recipe Dockerfile as a cacheable Buildx build definition, but reduce
  its final scratch stage to the local binary export contract used by the host
  script. Remove runtime-image labels, notice/source packaging, and entrypoints.
- Update current user, contributor, recipe, and distribution-notice contracts
  so they describe committed binaries, local builds, tracked source archives,
  and builder images without promising utility containers.
- Preserve every committed utility byte/mode, catalog row, tracked source and
  source lock, builder lock/digest, and public builder repository/tag.

Out of scope:

- Deleting existing utility packages or utility-scoped Actions caches; the
  ordered follow-up plan owns that destructive external cleanup.
- Publishing binaries as GitHub Release assets, generating standalone checksum
  indexes, or introducing a new binary package format.
- Changing or republishing builders, tracked source inputs, source-input policy,
  recipes, feature sets, versions, or static-link validation.
- Deleting historical Actions runs or rewriting completed plan records, which
  accurately describe earlier repository behavior.
- Broad BuildKit blob-cache deletion; builder and utility jobs share the blob
  namespace, so only exact utility scope indexes may be retired safely.

## Design

The supported ownership model becomes:

- `artifacts/<architecture>/<tool>` is the distributed executable.
- `recipes/<tool>/<architecture>/` owns the reproducible build and validation.
- `builders/<architecture>/environment.lock` selects an immutable builder from
  the sole GHCR package, `ghcr.io/w0ot-net/static_bins-builder`.
- Recipe-local `sources/` directories retain the checksum-locked upstream
  inputs established by the prerequisite source migration; they are not binary
  or container distribution endpoints.

Keep `recipes/catalog.tsv` unchanged as
`name<TAB>architecture<TAB>enabled`. `enabled=true` means the tool is available
to `./build.sh list`, `./build.sh <name>`, and repository validation. It no
longer implies registry publication. `scripts/recipes.py validate` continues to
check catalog shape, globally unique names, conventional paths, executable Git
modes, source metadata, notices/inventories, and pinned builder digests. Remove
the `matrix` command plus `Recipe` fields and architecture mappings used only
for image names, tags, cache scopes, native runners, and OCI platforms. Retain
source-version validation as a source-lock invariant, not publication metadata.

Use a Git-aware rename from `.github/workflows/publish-containers.yml` to
`.github/workflows/validate-recipes.yml`. The replacement runs on ordinary
Ubuntu for pushes to `main` affecting the dispatcher, catalog,
validator/tests, builders, recipes, artifacts, or itself, with manual dispatch
retained for maintainers. It needs only `contents: read` and runs the Python
validator/unit tests, `./build.sh list`, and cheap syntax checks. It must not set
up Docker, request package write access, build utilities, or emit a publication
matrix.

A recipe Dockerfile remains useful for BuildKit caching and for exporting the
guest build result. Its final stage is explicitly a local artifact-export stage:
`FROM scratch AS artifact` followed by the one `COPY --from=builder` needed to
place the executable at the path expected by `--output type=local`. License and
source material remain tracked beside the recipe; they are not redundantly
copied into a nonexistent runtime package. The builder stage and guest-side
build commands must remain unchanged.

Make the repository changes in one implementation commit so the push evaluates
only the new validation workflow. Record artifact hashes and Git modes first.
After all Dockerfile cleanup is complete, exercise each affected recipe exactly
once through the supported Buildx host command, using native/cacheable execution
where available; do not repeat builds for documentation or late validation.
Any unexpected binary change is a stop condition for this policy-only cleanup.

## Affected Components

- `.github/workflows/publish-containers.yml` ->
  `.github/workflows/validate-recipes.yml`: replace utility building and GHCR
  publication with fast catalog, unit, dispatcher, and syntax validation.
- `scripts/recipes.py`: retain strict recipe validation while deleting the CI
  matrix emitter and image/tag/cache/runner/platform derivations.
- `tests/test_recipes.py`: remove matrix/publication fixtures and assertions;
  retain and focus catalog, lock, path/mode, enabled-state, and dispatcher
  coverage for both supported recipe lock shapes.
- `recipes/gdb/aarch64/Dockerfile` and
  `recipes/tcpdump/x86_64/Dockerfile`: keep builder behavior and binary export,
  but remove runtime-image-only metadata, files, and entrypoints.
- `README.md`, `AGENTS.md`, and `doc/adding-a-binary.md`: define the binary-only
  distribution model, builder-only GHCR contract, and validation-only CI.
- `recipes/{gdb/aarch64,tcpdump/x86_64}/README.md` and
  `recipes/{gdb/aarch64,tcpdump/x86_64}/licenses/NOTICE.md`: remove artifact-image
  wording while preserving source, license, provenance, and build facts.

## Implementation Sequence

1. Wait for in-flight plan work and workflows to finish. Require a clean,
   synchronized `main`, then record both reproducible artifact hashes/modes,
   both builder lock digests, catalog contents, and the live set of references
   to utility publication.
2. Git-move the publication workflow to the validation workflow and replace its
   jobs, triggers, and permissions with the fast checks above.
3. Remove matrix-only Python state and tests while preserving every current
   source-lock and recipe-integrity check delivered by preceding plans.
4. Reduce both Dockerfile final stages to binary export without changing either
   builder stage, guest script, source input, or output filename.
5. Update the nearest live documentation and notices. Search all live files for
   utility package names and publication terms; allow builder publication and
   historical completed records only.
6. Run fast validation, then run each affected recipe once through its supported
   Buildx command. Compare artifact hashes/modes with the recorded baseline and
   stop rather than commit an unexplained binary change.
7. Explicitly stage the bounded files, commit and push the cleanup atomically,
   wait for the new validation workflow, and verify the push did not create a
   utility-image workflow run or a new GHCR utility package version.

## Validation

- Run `python3 scripts/recipes.py validate`,
  `python3 -m unittest tests.test_recipes`, and `./build.sh list`; require both
  enabled recipes to validate and list without a `matrix` CLI path.
- Run Bash/sh syntax checks for changed scripts, parse every workflow YAML file,
  run ShellCheck when available, and run `git diff --check`.
- Inspect the replacement workflow and require `contents: read`, no
  `packages: write`, no Docker setup/login/build action, no registry/tag/cache
  composition, and no native recipe matrix.
- Run `./build.sh gdb` and `./build.sh tcpdump` once after the final Dockerfile
  edits, reusing native/cacheable execution. Confirm Buildx local output still
  supplies the expected binary and all target/static/version/focused smoke tests
  pass. Do not dispatch the retired publication workflow as validation.
- Compare the before/after SHA-256 and Git index mode of
  `artifacts/aarch64/gdb` and `artifacts/x86_64/tcpdump`; require no artifact
  change from this distribution-policy cleanup. Confirm all other artifacts are
  untouched.
- Search live code and current documentation (excluding completed plans and
  third-party license prose) for `static_bins-gdb`, `static_bins-tcpdump`,
  `publish-containers`, `artifact image`, `image_name`, `tag_suffixes`,
  `cache_scope`, and the matrix command. Only builder-image and historical
  references may remain.
- After the push, require the validation workflow to succeed and compare GHCR
  utility package version counts with the pre-push snapshot to prove nothing
  was republished.

## Success Criteria

- GHCR publication code exists only for `static_bins-builder`; no repository
  workflow can create or update a utility package.
- The catalog and validator own build availability and recipe integrity only,
  with no image/tag/cache/runner/platform matrix state.
- `./build.sh gdb` and `./build.sh tcpdump` still use their exact locked builder
  digests and produce the same validated committed executables.
- Recipe Dockerfiles serve local Buildx export and caching without defining a
  distributed runtime package contract.
- Current documentation consistently directs users to committed binaries and
  recipes while describing GHCR as builder-only.
- Fast validation runs on relevant changes without compiling or publishing
  every utility.

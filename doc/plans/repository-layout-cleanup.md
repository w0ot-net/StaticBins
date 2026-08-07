# Plan: Simplify Repository Layout and Naming

## Summary

Reorganize the repository around three obvious owners: `artifacts/` for
committed binaries, `recipes/` for tool builds, and `builders/` for reusable
architecture environments. Normalize the internal x86 architecture name to
`x86_64`, reduce `recipes/catalog.tsv` to the three facts that cannot be
derived, and preserve the root `./build.sh <name>` interface plus all existing
binary bytes and published GDB contracts.

## Problem

The current paths encode architecture, Alpine, object type, and implementation
detail in names such as `aarch64_alpine_build_scripts/` and `x64_bins/`.
Builder lifecycle files and tool recipes share those directories, while the
legacy tcpdump script uses a third flat layout. Architecture terminology also
mixes `x64`, x86-64, `x86_64`, AArch64, and OCI `amd64`/`arm64` without a clear
boundary.

The catalog compounds this by storing 11 columns even though recipe paths,
output paths, source version, image name, tags, cache scope, platform, and
runner all follow repository conventions or already have an authoritative
owner. This makes the landing page and onboarding contract look more complex
than the actual user operation, which is already the good and stable
`./build.sh <name>` interface.

## Scope

In scope:

- Move committed binaries to `artifacts/<architecture>/`, reusable builder
  definitions to `builders/<architecture>/`, and tool builds to
  `recipes/<tool>/<architecture>/` using Git-aware moves that preserve modes
  and history.
- Use `aarch64` and `x86_64` as the only internal architecture identifiers;
  translate them to OCI `arm64` and `amd64` only at Docker/workflow boundaries.
- Move the nonconforming tcpdump script to
  `recipes/tcpdump/x86_64/legacy.sh` without registering or presenting it as a
  reproducible recipe.
- Move the publication allowlist to `recipes/catalog.tsv` and reduce it to
  `name`, `architecture`, and `enabled`; derive the
  source version from `source.lock` and every other publication/build value
  from the validated name/architecture convention.
- Migrate every live script, workflow, test, notice, README/AGENTS contract,
  onboarding document, and the active tcpdump plan to the new paths and names.
- Keep the root `./build.sh list` and `./build.sh gdb` commands stable, preserve
  existing artifact bytes, and retain existing public GDB and builder image
  tags/digests.

Out of scope:

- Adding AArch64 gdbserver or migrating any legacy x86-64 binary into a
  reproducible/published recipe.
- Choosing a repository-wide source-code license, adding `SHA256SUMS`, or
  publishing direct binary release assets; those are independent distribution
  policy and delivery outcomes.
- Renaming the GitHub repository, GHCR repositories, immutable source release,
  or already published builder tags. In particular, the existing public
  `x64-*` builder tags remain compatibility identifiers at the external
  registry boundary.
- Generalizing the GDB-specific source-mirror workflow for multiple tools.
- Rewriting completed plan records, whose old paths are historical facts.
- Adding compatibility wrappers or symlinks for old deep implementation paths;
  only the documented root build interface is a stable user contract.

## Design

The target domain layout is:

```text
artifacts/
  aarch64/gdb
  x86_64/{gdbserver,lsof,socat,strace,tcpdump}
builders/
  aarch64/{Dockerfile,build.sh,environment.lock,packages.lock,run.sh}
  x86_64/{Dockerfile,build.sh,environment.lock,packages.lock}
recipes/
  gdb/
    aarch64/{Dockerfile,build.sh,build-in-container.sh,source.lock,licenses/,README.md}
  tcpdump/
    x86_64/legacy.sh
```

`doc/`, `scripts/`, `tests/`, `.github/`, and `build.sh` remain at the root.
Keep `doc/` rather than creating a second `docs/` tree because the
repository's planning workflow already owns `doc/plans/` and
`doc/completed_plans/`.

Architecture translation is explicit and bounded:

| Internal name | Artifact directory | Docker platform | Native runner | New artifact tag suffix |
| --- | --- | --- | --- | --- |
| `aarch64` | `artifacts/aarch64` | `linux/arm64` | `ubuntu-24.04-arm` | `aarch64` |
| `x86_64` | `artifacts/x86_64` | `linux/amd64` | `ubuntu-24.04` | `x86_64` |

The x86-64 environment lock may continue to record its already published
`x64-alpine-*` builder tag. The builder workflow maps internal `x86_64` to that
legacy external tag prefix and floating `x64-latest` alias rather than
republishing or pretending those registry names changed.

`recipes/catalog.tsv` becomes:

```text
name<TAB>architecture<TAB>enabled
gdb<TAB>aarch64<TAB>true
```

`scripts/recipes.py` remains the authoritative strict validator and matrix
emitter. From a validated row it derives
`recipes/<name>/<architecture>/build.sh`,
`artifacts/<architecture>/<name>`,
`builders/<architecture>/environment.lock`, the Docker context/file, native
runner, platform, `static_bins-<name>` image name, cache scope, and versioned
and floating tag suffixes. It reads `SOURCE_VERSION` directly from the recipe's
`source.lock`; no second version owner remains. The workflow composes the GHCR
namespace from the current repository owner, while credentials, fixed build
arguments, OCI labels, SBOM, and provenance stay in workflow code.

The Bash dispatcher parses only the three-column allowlist, validates the name,
architecture, uniqueness, and enabled state, derives the one conventional
script path, and `exec`s it. It does not invoke Python or reproduce publication
metadata. Tests continue to read executable bits from the Git index so the
shared filesystem's permissive modes cannot hide a bad commit.

Move GDB-specific usage and feature detail out of the landing page into
`recipes/gdb/aarch64/README.md`. Keep the root README limited to what the
repository provides, the artifact table, `./build.sh list`,
`./build.sh <name>`, container locations, and links to recipe/maintainer detail.

## Affected Components

- `aarch64_bins/*` and `x64_bins/*` -> `artifacts/{aarch64,x86_64}/*`: move all
  committed payloads without changing bytes or executable Git modes.
- `aarch64_alpine_build_scripts/*` and `x64_alpine_build_scripts/*` ->
  `builders/{aarch64,x86_64}/*`, `recipes/gdb/aarch64/*`, and
  `recipes/tcpdump/x86_64/legacy.sh`: separate builder, conforming recipe, and
  legacy ownership; rename builder entry points and package locks consistently.
- `recipes.tsv` -> `recipes/catalog.tsv`, plus `build.sh` and
  `scripts/recipes.py`: move and reduce the catalog to the three-column
  allowlist and derive dispatcher/matrix values by convention.
- `tests/test_recipes.py`: migrate fixtures and assertions to the new layout,
  test version derivation from `source.lock`, and retain malformed, collision,
  disabled, path/mode, deterministic-matrix, and dispatcher coverage.
- `.github/workflows/{publish-builder,publish-containers,mirror-sources}.yml`:
  update contexts/path filters and architecture mapping while preserving locked
  inputs, publication policy, source release identity, and public image names.
- `.gitattributes`: follow the moved verbatim license texts.
- `README.md`, `AGENTS.md`, `doc/adding-a-binary.md`, and
  `recipes/gdb/aarch64/{README.md,licenses/NOTICE.md}`: state the new concise
  public, contributor, and recipe-local contracts.
- `doc/plans/05-rebuild-x64-tcpdump.md` ->
  `doc/plans/05-rebuild-x86-64-tcpdump.md`: rename and mechanically rebase the
  still-active plan onto `recipes/tcpdump/x86_64`, `builders/x86_64`,
  `artifacts/x86_64/tcpdump`, the minimal catalog, and canonical internal
  architecture/tag names; remove its obsolete deep-path compatibility wrapper.

## Implementation Sequence

1. Record SHA-256 values and Git modes for every committed binary and the
   locked builder/source inputs before moving anything.
2. Use Git-aware moves to create `artifacts/`, `builders/`, and `recipes/`,
   rename builder entry points/locks, and relocate the legacy tcpdump script.
   Do not add old-path wrappers or duplicate files.
3. Reduce the catalog and update the Python validator/matrix plus focused tests
   so all paths, version, image/tag, runner/platform, environment, and cache
   values have one conventional derivation.
4. Update the Bash dispatcher, GDB host script, builder scripts, all three
   workflows, and `.gitattributes` to consume the new owners. Preserve exact
   image digests and source/archive acceptance rules.
5. Shorten the root README, add recipe-local GDB instructions, update AGENTS
   and onboarding contracts, and rebase only the active tcpdump plan. Leave
   completed plans unchanged.
6. Run fast structural/unit validation first, compare all moved artifact hashes
   and modes, then run one native catalog-driven GDB publication and inspect
   the resulting public image. Reuse existing validated bytes/cache and do not
   repeat a local QEMU compilation solely to prove path changes.

## Validation

- Run `python3 -m unittest tests.test_recipes`,
  `python3 scripts/recipes.py validate`, compare two `matrix` invocations for
  identical compact JSON, and verify the matrix derives GDB 17.2 from the moved
  `source.lock`.
- Run `./build.sh list`; use controlled fixtures to prove unknown, unsafe,
  duplicate, disabled, malformed, missing-script, and extra arguments fail
  before execution and that dispatch preserves environment and exit status.
- Run Bash/sh syntax checks, parse every workflow YAML file, use ShellCheck when
  available, and run `git diff --check`.
- Compare the before/after SHA-256 and Git mode of all six committed binaries;
  run `file`/`readelf` spot checks at their new locations and require no binary
  content change from this migration.
- Confirm `git ls-files` contains no old `*_bins/` or
  `*_alpine_build_scripts/` paths. Search live code, configuration, and user
  documentation (excluding plan records) for old directory names and internal
  `x64` use; allow only the documented legacy public builder tag values.
- Verify the moved GDB host script resolves the repository root, builder lock,
  license/source inputs, and output path correctly. Exercise the new builder
  run command with `/bin/true` against the same locked public digest rather than
  rebuilding the builder.
- Confirm the source-mirror workflow still resolves the moved lock/notices and
  that the existing `gdb-17.2-source` release remains immutable and unchanged;
  do not attempt to republish it.
- Run the catalog-driven publication once on the native ARM runner. Confirm the
  catalog gate and GDB job succeed, anonymously pull both existing GDB tags,
  inspect OCI labels plus attestations, and compare `/gdb` with the unchanged
  committed artifact. Reuse the prior focused remote-debugging result when the
  payload hash is identical.
- Read the updated active tcpdump plan end to end and verify its paths,
  architecture terminology, catalog assumptions, and success criteria match
  the new repository contract before later execution.

## Success Criteria

- The top-level domain layout is immediately understandable as `artifacts/`,
  `builders/`, and `recipes/`; no live old architecture-prefixed bin/build
  directories or mixed builder/recipe owner remain.
- Internal architecture names are consistently `aarch64` and `x86_64`, with
  OCI and legacy published-tag translations confined to explicit boundary
  mappings.
- `recipes/catalog.tsv` contains only `name`, `architecture`, and `enabled`;
  every other build/publication value has one validated conventional or
  lock-file owner.
- `./build.sh gdb` remains the stable one-command interface, and adding a future
  conforming recipe requires its conventional directory plus one minimal row,
  without a workflow edit.
- Every committed binary retains its exact bytes and executable mode, and the
  existing immutable source release, locked builder digests, GDB GHCR names,
  GDB versioned/floating tags, SBOM, provenance, and runtime behavior remain
  intact.
- The concise root README, recipe-local GDB documentation, onboarding guide,
  AGENTS contract, tests, workflows, and active tcpdump plan all describe the
  same layout and naming model.

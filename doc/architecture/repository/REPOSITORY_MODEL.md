# Repository model

This page owns directory responsibilities, recipe identity, and the boundary
between generic orchestration and tool-specific policy. Return to the
[architecture index](../README.md).

## Ownership

- `artifacts/<architecture>/<tool>` is the distributed executable.
- `recipes/<tool>/<architecture>/` owns source locks, tracked inputs,
  configuration, licenses, build logic, smoke tests, and tool documentation.
- `builders/<architecture>/` owns the reusable package environment and its
  immutable publication lock.
- `recipes/catalog.tsv` is the minimal allowlist consumed by the dispatcher and
  validator.
- `scripts/` and root `build.sh` provide generic validation and dispatch.

A recipe's identity is the pair `(name, architecture)`. The catalog contains
only `name`, `architecture`, and `enabled`; conventional recipe, artifact, and
builder paths are derived from that pair. Source versions and authentication
come from the recipe's `source.lock`, not the catalog.

The supported internal architecture identifiers are `aarch64`, `armv7`, and
`x86_64`. They name repository directories and executable host architecture.
Container-platform translations belong at the build-environment boundary, as
documented in [Build environments](../build/BUILD_ENVIRONMENTS.md).

## Dispatch and validation

`./build.sh list` emits enabled `(name, architecture)` pairs. A tool name may be
used without an architecture only when exactly one catalog row has that name;
otherwise the caller must select a pair explicitly. The dispatcher rejects
unsafe names, unsupported architectures, malformed rows, duplicate pairs, and
missing enabled build scripts before execution.

`scripts/recipes.py` applies the fuller repository contract: conventional
ownership, tracked regular inputs, executable modes, source authentication,
immutable builder references, and the complete artifact manifest. Generic code
derives paths and selects owners; it does not contain tool versions, configure
flags, license judgments, or smoke-test policy.

See the [contributor procedure](../../adding-a-binary.md) for how to add a
conforming pair.

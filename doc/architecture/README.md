# System architecture

This tree owns the stable responsibilities and interactions of `static_bins`.
The system begins with reviewed upstream inputs and ends with standalone Linux
executables distributed from Git. GHCR supplies reusable build environments,
not utility containers.

```text
official upstream
       |
       v
tracked archive + source.lock + authentication/license evidence
       |
       v
recipe + immutable architecture builder digest
       |
       v
Buildx guest build -> temporary candidate -> ELF and functional checks
       |
       v
artifacts/<architecture>/<tool> -> artifacts/SHA256SUMS
```

Repository validation authenticates and checks tracked inputs independently of
the artifact build shown above. Independent exact rebuilds or attestations may
be retained as supplemental historical evidence, but they are not part of the
normal acceptance path. A failure at either required boundary stops the
relevant operation.

## Authority rules

- The root [`README.md`](../../README.md) owns concise user entry points and
  current artifact links.
- [`TRUST.md`](../../TRUST.md) owns live assurance rows, limitations, and user
  verification commands.
- [`doc/adding-a-binary.md`](../adding-a-binary.md) owns contributor procedure.
- [`AGENTS.md`](../../AGENTS.md) owns concise automated-contributor guardrails.
- Recipe READMEs own tool versions, features, prerequisites, and behavior.
- These architecture pages own stable system responsibilities and interactions.
- Active and completed plans are implementation records, not current
  architecture.

## Reading order

1. [Repository model](repository/REPOSITORY_MODEL.md) for ownership and recipe
   identity.
2. [Source inputs](build/SOURCE_INPUTS.md), [build environments](build/BUILD_ENVIRONMENTS.md),
   and the [build pipeline](build/BUILD_PIPELINE.md) for manufacturing.
3. [Artifact contract](artifacts/ARTIFACT_CONTRACT.md) for installed-output
   guarantees.
4. [Trust chain](trust/TRUST_CHAIN.md) and
   [automation and governance](trust/AUTOMATION_AND_GOVERNANCE.md) for assurance
   and control boundaries.
5. [Distribution model](distribution/DISTRIBUTION_MODEL.md) for the public
   delivery surfaces.

The broader [documentation map](../README.md) links every page and its nearest
operational authority.

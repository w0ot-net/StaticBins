# Documentation map

This page routes readers to the current authority for each kind of information.
Architecture pages explain stable system responsibilities; they do not replace
the live user, trust, contributor, or recipe documentation.

## Current authorities

- [`README.md`](../README.md) is the concise user entry point and current
  artifact index.
- [`TRUST.md`](../TRUST.md) owns current source and artifact assurance status,
  limitations, and verification commands.
- [`adding-a-binary.md`](adding-a-binary.md) is the contributor procedure.
- [`AGENTS.md`](../AGENTS.md) contains repository guardrails for automated
  contributors.
- Each `recipes/<tool>/<architecture>/README.md` owns its tool's version,
  features, prerequisites, and build behavior.
- The [architecture index](architecture/README.md) explains how the complete
  manufacturing and distribution system fits together.

## Architecture topics

- [Repository model](architecture/repository/REPOSITORY_MODEL.md)
- [Build pipeline](architecture/build/BUILD_PIPELINE.md)
- [Source inputs](architecture/build/SOURCE_INPUTS.md)
- [Build environments](architecture/build/BUILD_ENVIRONMENTS.md)
- [Artifact contract](architecture/artifacts/ARTIFACT_CONTRACT.md)
- [Trust chain](architecture/trust/TRUST_CHAIN.md)
- [Automation and governance](architecture/trust/AUTOMATION_AND_GOVERNANCE.md)
- [Distribution model](architecture/distribution/DISTRIBUTION_MODEL.md)

## Implementation records

[`plans/`](plans/) contains accepted work that has not been completed.
[`completed_plans/`](completed_plans/) records how prior changes were executed.
Neither directory defines current behavior; use the authorities above.

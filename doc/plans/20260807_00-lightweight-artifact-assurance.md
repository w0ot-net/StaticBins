# Plan: Simplify Artifact Assurance to Local Validated Builds

## Summary

Make the committed tool-owned recipe and its strict local Buildx validation the
normal authority for producing distributed artifacts. Keep GitHub Actions as a
fast repository-integrity check, but remove utility compilation, exact rebuild,
and new attestation requirements from CI. Replace the binary `verified` label
with factual build and independent-evidence records in `TRUST.md`.

## Problem

The current trust contract equates the strongest artifact status with a clean
native GitHub rebuild and attestation. That adds architecture-specific runner,
selection, and operational work beyond the repository's primary goal of small,
documented, repeatable local recipes. It also produces the vague label `Not
verified` for artifacts that have passed all recipe-owned source, static ELF,
architecture, and functional checks but have not been rebuilt by a second
machine.

The maintainer's threat model does not require protection against a compromised
maintainer workstation. Requiring GitHub or self-hosted compilation therefore
adds complexity without serving a required trust boundary, and it becomes less
practical as more emulated architectures are added.

## Scope

In scope:

- Define a committed artifact as maintainer-built by its conventional recipe
  only after all source, link, ELF, architecture, stripping, version, and
  functional checks pass locally through the locked Buildx path.
- Keep `recipe-validation` and `artifact-assurance` as stable, fast CI signals;
  neither job compiles utility binaries.
- Make `artifact-assurance` check the committed catalog/artifact relationship,
  source evidence, modes, manifest completeness, and exact SHA-256 values using
  the existing offline validator and standard checksum tools.
- Replace the two-value artifact status in `TRUST.md` with factual build-record
  and independent-evidence columns, retaining the existing tcpdump attestation
  as historical supplemental evidence.
- Update the nearest repository, contributor, artifact, trust, and automation
  authorities to state the simplified contract.

Out of scope:

- Rebuilding any artifact, changing any committed executable or checksum, or
  weakening recipe-owned target-architecture validation.
- Adding local signing keys, release archives, hardware labs, self-hosted
  runners, cross-architecture CI builds, or new provenance attestations.
- Deleting the existing tcpdump attestation from GitHub or claiming that a
  checksum proves how an artifact was built.

## Design

Preserve the existing manufacturing path: a maintainer runs
`./build.sh <tool> <architecture>`, which consumes tracked source bytes and the
immutable builder, validates a temporary candidate on the target architecture,
and replaces the artifact only after every recipe check succeeds. QEMU is an
ordinary supported execution backend where native container execution is
unavailable; it does not create a different artifact status.

Simplify `.github/workflows/verify-artifacts.yml` to one fast
`artifact-assurance` job. It checks out the repository with read-only contents,
runs `python3 scripts/recipes.py validate`, and checks
`artifacts/SHA256SUMS` strictly. Remove the change selector, Docker Buildx
setup, build matrices, OIDC/attestation permissions, and artifact compilation.
Keep the stable workflow/job identity so existing CI consumers continue to see
the signal. `validate-recipes.yml` remains the broader catalog/unit/syntax
workflow and may overlap intentionally on the core offline integrity check.

Reshape the artifact table in `TRUST.md` around orthogonal facts:

- source authentication remains `Upstream PGP` or `Checksum only`;
- build record states that the artifact was maintainer-built through the
  committed recipe and passed its recipe validation;
- independent evidence is either `None recorded` or a precise historical
  attestation/rebuild record.

Do not replace `Not verified` with another single confidence label. Checksums
continue to prove equality with the checked-out repository, not authorship or
provenance. The historical x86-64 tcpdump attestation and verification command
remain documented, but future artifacts do not need equivalent GitHub builds.

## Affected Components

- `AGENTS.md`: make local locked-recipe validation the artifact acceptance gate
  and remove mandatory native qualification/new attestation rules.
- `.github/workflows/verify-artifacts.yml`: retain a lightweight stable
  `artifact-assurance` job without utility builds or elevated permissions.
- `README.md`: describe checksum and TRUST verification without implying that
  un-attested artifacts failed recipe validation.
- `TRUST.md`: replace binary status labels with factual build and independent
  evidence, preserving historical tcpdump provenance.
- `doc/adding-a-binary.md`: document the local validated build, checksum, and
  trust-record procedure without CI qualification.
- `doc/architecture/artifacts/ARTIFACT_CONTRACT.md`: make recipe validation and
  manifest integrity the required artifact boundary; describe independent
  rebuilds as optional evidence.
- `doc/architecture/trust/TRUST_CHAIN.md`: separate required local validation
  from optional independent reproduction/provenance.
- `doc/architecture/trust/AUTOMATION_AND_GOVERNANCE.md`: document the fast
  artifact-assurance role and removal of build/attestation permissions.

## Implementation Sequence

1. Update the repository and architecture contracts together so the intended
   trust model is explicit before changing workflow behavior.
2. Simplify `verify-artifacts.yml` to the read-only fast integrity job while
   preserving the workflow and `artifact-assurance` job names.
3. Rewrite the live TRUST artifact table and README/contributor wording. Keep
   every existing artifact and its source authentication, and retain the exact
   historical tcpdump attestation facts and command.
4. Run focused workflow, document, catalog, manifest, and repository checks;
   commit and push only the policy/workflow/documentation paths.

## Validation

- Parse `.github/workflows/verify-artifacts.yml` as YAML, validate every
  embedded shell block, and require all retained `uses:` references to remain
  pinned to full commit SHAs.
- Run `python3 scripts/recipes.py validate`,
  `python3 -m unittest tests.test_recipes`, `./build.sh list`, and
  `sha256sum --check --strict artifacts/SHA256SUMS`.
- Run shell syntax checks, ASCII checks for changed text, and
  `git diff --check`.
- Inspect the diff to confirm no recipe, builder, artifact, source archive,
  checksum record, catalog row, or historical attestation claim changed.
- Require the pushed `recipe-validation` and lightweight
  `artifact-assurance` jobs to pass without starting Docker or compiling a
  utility.

## Success Criteria

- Repository policy clearly accepts locally Buildx/QEMU-built artifacts after
  their committed recipe validation, without requiring a GitHub rebuild.
- CI retains both stable signal names and validates exact committed state with
  no utility compilation, self-hosted runner, or elevated attestation
  permission.
- `TRUST.md` reports source, local build validation, and independent evidence
  as separate facts; existing tcpdump evidence is preserved and all other
  artifacts are described without the ambiguous `Not verified` label.

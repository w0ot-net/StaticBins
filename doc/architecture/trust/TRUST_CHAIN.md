# Trust chain

This page owns how the repository's assurance layers compose and what they do
not prove. Return to the [architecture index](../README.md).

1. Tracked checksums and declared PGP or checksum-only evidence establish the
   accepted source bytes and, where supported, upstream origin.
2. Committed source archives ensure ordinary builds consume the reviewed bytes
   without depending on current upstream availability.
3. Exact package and environment locks constrain the reusable builder; its
   immutable digest, SBOM, and provenance identify the published environment.
4. Recipe configuration and final-link inventory identify the selected feature
   profile and every linked static archive with source and license evidence.
5. ELF and target-architecture smoke tests establish bounded structural and
   functional properties of the produced candidate.
6. The artifact manifest detects changes relative to committed history.
7. Optional independent rebuild or attestation evidence can bind exact bytes
   to a separate build execution and source revision; it is recorded as an
   additional fact rather than an acceptance requirement.
8. Protected history prevents deletion and non-fast-forward replacement of the
   accepted `main` lineage.

Each link answers a different question. A checksum is not origin evidence; a
valid signature is not build provenance; a static binary is not necessarily
correct; an attestation does not make source safe; and protected history does
not review or approve a commit.

Residual trust includes upstream maintainers and signing practices, Alpine and
builder inputs, repository writers and settings administrators, local Docker
execution and registry credentials, GHCR, and the review quality of recipe and
license evidence. Historical attestations additionally depended on GitHub's
identity, Actions, and attestation services. None of the chain proves that a
program is benign, vulnerability-free, or legally compatible.

[`TRUST.md`](../../../TRUST.md) remains the authority for current source
fingerprints, artifact records, limitations, and verification commands. See
[automation and governance](AUTOMATION_AND_GOVERNANCE.md) for control flow.

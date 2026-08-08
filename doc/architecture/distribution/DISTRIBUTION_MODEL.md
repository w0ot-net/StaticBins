# Distribution model

This page owns the boundary between utility, builder, source, checksum, and
license distribution. Return to the [architecture index](../README.md).

Standalone executables under `artifacts/<architecture>/` are the only utility
distribution surface and form the current public artifact set.
`artifacts/SHA256SUMS` is their complete exact inventory, and enabled rows in
`recipes/catalog.tsv` identify the pairs exposed by generic build dispatch.
Users obtain the executables from the Git repository or its raw-file links and
verify them with the checksum manifest. The root
[`README.md`](../../../README.md) links to these authorities without duplicating
their changing inventory.

GHCR publishes reusable architecture build environments only. Utility runtime
images would add an unnecessary execution and ownership surface, so recipe
Dockerfiles export local candidate files and do not define or publish utility
containers.

Exact reviewed source archives and their authentication evidence remain under
each recipe's `sources/` directory. This keeps normal builds independent of
upstream availability and keeps each distributed binary adjacent to its source
and build evidence. The project does not use repository releases as a second
source or utility distribution channel.

The checksum manifest detects file changes but does not establish authorship or
provenance. Current assurance claims and attestation commands remain in
[`TRUST.md`](../../../TRUST.md).

Each recipe also distributes upstream project notices and the license material
for linked inputs. The final-link inventory records their factual ownership,
versions, declared licenses, and immutable source references. Adding an
artifact requires reviewing and satisfying upstream source, notice, and offer
obligations; the inventory is evidence, not a legal conclusion.

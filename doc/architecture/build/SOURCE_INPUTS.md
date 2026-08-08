# Source inputs

This page owns the tracked-source and authentication boundary. Return to the
[architecture index](../README.md).

Every recipe has one committed `source.lock` and a `sources/` directory. Each
required upstream archive is a regular tracked mode-`100644` file whose
SHA-256, official HTTPS provenance URL, license identifier, and explicit
authentication mode are recorded in the lock. Multi-source recipes keep every
record and byte under the same tool-and-architecture owner. The mandatory
record uses `SOURCE_`; each additional record uses another uppercase prefix
with the same `VERSION`, `ARCHIVE`, `SHA256`, `UPSTREAM_URL`, `LICENSE`, and
`AUTHENTICATION` fields. Repository validation discovers those complete records
from their `<PREFIX>VERSION` fields and applies the same checks without
tool-specific branches.

The accepted authentication modes are:

- `pgp`: the recipe also tracks the detached signature, a minimal signer
  keyring, and the exact full fingerprint. Repository validation uses `gpgv`
  offline and fails closed on any mismatch.
- `checksum-only`: the absence of adopted signer evidence is explicit. It is a
  weaker assurance level, not a fallback after failed PGP verification.

`scripts/recipes.py` authenticates tracked inputs and verifies their recorded
checksums. During an artifact build, the guest copies only those tracked bytes
and rechecks each checksum immediately before extraction. Official URLs record
origin and support reviewed source updates; ordinary builds do not download
from them.

A downloaded full-system smoke-test kernel or base image is a separate
validation-environment input, not an upstream tool source. A recipe that
genuinely requires one records its immutable URL, checksum, and authentication
level in a dedicated lock, verifies it before boot, and caches it only outside
the tracked tree. It must not treat that input as linked source or copy it into
the distributed artifact.

Source updates use temporary storage: fetch from the recorded official URL,
verify checksum and declared authentication, inspect hosting size, review the
contents, and explicitly commit the accepted bytes and evidence. The repository
does not publish source-only release mirrors.

Each recipe's `licenses/` directory retains reviewed project and linked-input
materials. Its final-link archive inventory maps every external static archive
to an exact package, version, declared license, copied license file, and
immutable package source. The build fails on extra, missing, differently owned,
or differently licensed linked inputs.

Current fingerprints and assurance limitations remain in [`TRUST.md`](../../../TRUST.md).
The procedural checklist is in [`adding-a-binary.md`](../../adding-a-binary.md).

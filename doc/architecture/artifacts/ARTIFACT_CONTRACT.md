# Artifact contract

This page owns the guarantees required before a file replaces a distributed
artifact. Return to the [architecture index](../README.md).

`artifacts/<architecture>/<tool>` must be a regular tracked executable with Git
mode `100755`. The directory name promises the executable's host architecture,
not merely the data or target formats the tool understands.

A recipe validates a temporary candidate before installation, running target
checks either natively or through its supported Buildx/QEMU path. Executable
type and static linkage are separate facts. The repository accepts a
recipe-selected classic static `ET_EXEC` profile or static PIE `ET_DYN`
profile; the recipe enforces one exact choice so an unreviewed toolchain-output
change fails closed.

Both profiles use `file` and `readelf` to require the expected ELF machine,
class, endianness, ABI, and stripping state; reject a `PT_INTERP` program header
and every `DT_NEEDED` entry; and run the exact version plus the recipe's focused
target-architecture test. A static PIE additionally has a nonzero entry point,
at least one executable `PT_LOAD`, and `DF_1_PIE`, with no `DT_TEXTREL` tag or
`DF_TEXTREL` flag. `-static`, `-no-pie`, `file` wording, and `ET_DYN` or
`ET_EXEC` alone do not establish staticness.

ARMv7 artifacts also require ELF32, little-endian data, and the intended ARM
EABI hard-float flags. x86 artifacts require ELF32, little-endian data, an
`Intel 80386` machine field, and explicit compilation for the documented
i686-compatible CMOV/SSE2 baseline because the ELF machine field cannot
distinguish that CPU baseline.

New recipes and reviewed final-link policy changes must not use explicit
`-no-pie` merely to make static output look conventional. A recipe that
explicitly selects non-PIE `ET_EXEC` documents its concrete compatibility or
toolchain reason. Existing validated outputs do not require relinking solely to
change profile.

Only after those checks pass may the host install the candidate. It then repeats
the relevant ELF checks and requires the installed SHA-256 to equal the
validated candidate. A failed build or smoke test leaves the prior committed
file unchanged.

`artifacts/SHA256SUMS` is a sorted, complete, exact manifest for every
distributed file other than the manifest itself. Repository validation rejects
missing, extra, unsafe, duplicate, unsorted, wrong-mode, untracked, and
checksum-mismatched artifact state. It also requires the manifest's artifact
paths to equal the conventional outputs derived from `recipes/catalog.tsv`, so
every distributed file has exactly one validated recipe owner.

Three recorded assurance concepts remain distinct:

- Recipe build validation records that the maintainer-built candidate passed
  the committed source, link, structural, and target-functional checks.
- Exact rebuilding proves a fresh build produced the committed bytes.
- Provenance binds exact bytes to an identified build execution and source
  revision.

Recipe build validation is the artifact acceptance boundary. Exact rebuilds
and provenance attestations are optional independent facts; their absence does
not negate the target checks, and their presence does not make source safe.
[`TRUST.md`](../../../TRUST.md) records common acceptance facts once and lists
artifact-specific independent evidence as exceptions; artifacts not listed
there are explicitly defined as having none.

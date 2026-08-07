# Artifact contract

This page owns the guarantees required before a file replaces a distributed
artifact. Return to the [architecture index](../README.md).

`artifacts/<architecture>/<tool>` must be a regular tracked executable with Git
mode `100755`. The directory name promises the executable's host architecture,
not merely the data or target formats the tool understands.

A recipe validates a temporary candidate before installation, running target
checks either natively or through its supported Buildx/QEMU path. At minimum
it uses `file` and `readelf` to require the expected ELF machine, class,
endianness, and recipe-selected executable type; rejects a requested program
interpreter and every `DT_NEEDED` entry; checks stripping; and runs the exact
version plus a focused functional test on the target architecture. ARMv7
artifacts also require ELF32, little-endian data, and the intended ARM EABI
hard-float flags. x86 artifacts require ELF32, little-endian data, an `Intel
80386` machine field, and explicit compilation for the documented
i686-compatible CMOV/SSE2 baseline because the ELF machine field cannot
distinguish that CPU baseline.

Only after those checks pass may the host install the candidate. It then repeats
the relevant ELF checks and requires the installed SHA-256 to equal the
validated candidate. A failed build or smoke test leaves the prior committed
file unchanged.

`artifacts/SHA256SUMS` is a sorted, complete, exact manifest for every
distributed file other than the manifest itself. Repository validation rejects
missing, extra, unsafe, duplicate, unsorted, wrong-mode, untracked, and
checksum-mismatched artifact state.

Three recorded assurance concepts remain distinct:

- Recipe build validation records that the maintainer-built candidate passed
  the committed source, link, structural, and target-functional checks.
- Exact rebuilding proves a fresh build produced the committed bytes.
- Provenance binds exact bytes to an identified build execution and source
  revision.

Recipe build validation is the artifact acceptance boundary. Exact rebuilds
and provenance attestations are optional independent facts; their absence does
not negate the target checks, and their presence does not make source safe.
[`TRUST.md`](../../../TRUST.md) owns the current factual record for every
artifact and preserves any historical independent evidence.

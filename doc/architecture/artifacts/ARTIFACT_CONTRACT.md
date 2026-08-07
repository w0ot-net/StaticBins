# Artifact contract

This page owns the guarantees required before a file replaces a distributed
artifact. Return to the [architecture index](../README.md).

`artifacts/<architecture>/<tool>` must be a regular tracked executable with Git
mode `100755`. The directory name promises the executable's host architecture,
not merely the data or target formats the tool understands.

A recipe validates a temporary candidate before installation. At minimum it
uses `file` and `readelf` to require the expected ELF machine, class,
endianness, and recipe-selected executable type; rejects a requested program
interpreter and every `DT_NEEDED` entry; checks stripping; and runs the exact
version plus a focused functional test on the target architecture. ARMv7
artifacts also require ELF32, little-endian data, and the intended ARM EABI
hard-float flags.

Only after those checks pass may the host install the candidate. It then repeats
the relevant ELF checks and requires the installed SHA-256 to equal the
validated candidate. A failed build or smoke test leaves the prior committed
file unchanged.

`artifacts/SHA256SUMS` is a sorted, complete, exact manifest for every
distributed file other than the manifest itself. Repository validation rejects
missing, extra, unsafe, duplicate, unsorted, wrong-mode, untracked, and
checksum-mismatched artifact state.

Three assurance concepts remain distinct:

- Artifact validation proves stated structural and functional checks for one
  produced candidate.
- Exact rebuilding proves a fresh build produced the committed bytes.
- Provenance binds exact bytes to an identified build execution and source
  revision.

Attested status requires an explicit per-artifact qualification after one clean
native build reproduces the committed bytes. The same workflow job rebuilds,
compares, and attests that file. A mismatch remains `Not verified`; it is not
retried to search for favorable bytes. [`TRUST.md`](../../../TRUST.md) owns the
current status of every artifact.

# Plan: Qualify ARMv7 Artifacts on Native Hardware

## Summary

After all six ARMv7 artifacts exist, qualify their committed bytes with one
clean build on native ARM32 Linux and extend artifact assurance only for the
artifacts that reproduce exactly. Use an ephemeral, single-job ARM32
self-hosted runner restricted to the trusted main workflow; keep pull-request
comparisons on GitHub-hosted ARM64 under QEMU. Do not treat an emulated build as
equivalent to the repository's native attestation status.

## Problem

GitHub-hosted Linux provides x64 and ARM64 runners but no ARM32 runner. QEMU can
prove the ARMv7 ELF contract and run focused tests, and a GitHub-hosted emulated
job could attest its own build, but the repository defines
`Exact rebuild + GitHub attestation` as requiring a prior clean native rebuild.
A continuously registered self-hosted runner in a public repository would also
expose a serious untrusted-workflow persistence risk.

## Scope

In scope:

- Qualify each of GDB, GDBserver, lsof, socat, strace, and tcpdump once from a
  clean checkout on native ARM32 Linux with no QEMU/binfmt execution path.
- Provision the qualification runner as an ephemeral/JIT one-job runner with a
  dedicated ARM32 label and a mandatory runner-group restriction to the exact
  assurance workflow on `main`.
- Extend `.github/workflows/verify-artifacts.yml` with fail-safe per-artifact
  selection, GitHub-hosted emulated pull-request comparisons, native trusted
  main rebuild/compare/attest jobs, and the unchanged aggregate job name.
- Promote only exact native matches in `TRUST.md` and document the new runner
  trust boundary.

Out of scope:

- Leaving an ARM32 runner continuously registered, allowing fork or pull-request
  code onto it, storing runner registration credentials in the repository, or
  granting it repository contents write permission.
- Retrying a native mismatch, replacing committed artifact bytes to make a
  qualification pass, or promoting a QEMU-only match to native status.
- Building unrelated architectures or redesigning the two allowed artifact
  status labels.

## Design

Treat native qualification and ongoing attestation as a separate outcome from
recipe availability. The hardware/OS gate must report an ARM32 runner identity
and `uname -m` compatible with `armv7l`; Docker must execute the locked
`linux/arm/v7` builder without an enabled QEMU ARM binfmt handler. Record CPU,
kernel, Docker, Buildx, and runner versions in the job log, but derive trust
from exact build/compare behavior rather than a new repository state file.

Before changing the workflow, use a fresh checkout and empty BuildKit state on
the intended native host to run each `./build.sh <tool> armv7` exactly once.
Collect all matches and mismatches in one qualification pass. A mismatch stays
`Not verified` and is not retried; preserve diagnostics outside the repository
for analysis. Only matching artifacts enter the assurance matrix.

Never attach a persistent general-purpose runner to this public repository.
Queue the trusted main/manual job first, create a uniquely labeled JIT or
`--ephemeral` ARM32 runner for that one job, and restrict its runner group to
the assurance workflow at `refs/heads/main`. If the repository/account cannot
enforce that workflow restriction, stop and retain `Not verified` rather than
register the runner. Wipe its work directory or reimage the host after
de-registration. The native job checks out only the protected `main` commit,
uses read-only contents plus job-scoped OIDC/attestation permissions, rebuilds
one selected artifact, compares the manifest digest, and attests that same
file in the same job.

For pull requests, use `ubuntu-24.04-arm` plus the repository's pinned ARM
binfmt path to rebuild and compare selected ARMv7 artifacts without attesting
or accessing the self-hosted runner. Extend the existing selector narrowly so
an ARMv7 artifact is selected by its recipe, artifact, builder, catalog record,
manifest record, or assurance workflow boundary; preserve fail-safe selection
when comparisons cannot be computed. Keep `artifact-assurance` as the stable
aggregate signal.

## Affected Components

- `.github/workflows/verify-artifacts.yml`: add bounded ARMv7 selectors and
  emulated PR/native main matrices while preserving exact compare-and-attest
  semantics and the stable aggregate job name.
- `TRUST.md`: promote each successful native qualification, add exact `gh
  attestation verify` commands, and leave any mismatch explicitly unverified.
- `doc/architecture/trust/AUTOMATION_AND_GOVERNANCE.md`: document trusted-event
  routing, ephemeral ARM32 ownership, and the added self-hosted trust boundary.

## Implementation Sequence

1. Require all six recipe plans and artifacts to be complete and `Not
   verified`. Obtain dedicated ARM32-capable hardware and a supported ARM32
   Linux userland with enough memory/storage for the largest clean build.
2. Prove the runner/host gate with the runner offline from GitHub, clear build
   state, and perform one native qualification pass over all six committed
   artifacts. Do not retry mismatches.
3. Update the selector, PR comparison, native attestation matrix, TRUST records
   for matches, and automation authority page. Validate workflow syntax and
   event/job conditions before pushing.
4. Push the workflow commit to protected `main`, queue the selected trusted
   run, and only then register a one-job ephemeral/JIT runner restricted to
   that workflow and unique label.
5. Require each selected native job to rebuild, compare, and attest the same
   bytes. Verify every new attestation anonymously, de-register and wipe the
   runner, and record no claim for any failure.

## Validation

- Parse the workflow as YAML; validate every embedded Bash block, all
  40-character action pins, `git diff --check`, and the stable job names
  `recipe-validation` and `artifact-assurance`.
- Exercise selector fixtures or bounded shell tests for each ARMv7 recipe,
  artifact, manifest, catalog, builder, workflow, unrelated, and comparison
  failure path.
- On PR behavior, require GitHub-hosted ARM64/QEMU jobs to compare exact bytes
  without `id-token` or attestation permission and without routing to a
  self-hosted label.
- On native behavior, require `armv7l`, no ARM QEMU binfmt handler, a clean
  build, exact manifest comparison before attestation, read-only contents, and
  one artifact per attestation job.
- Verify each successful attestation with repository, signer workflow, source
  ref, and subject path constraints; confirm the ephemeral runner is gone and
  its workspace is wiped afterward.

## Success Criteria

- Every promoted ARMv7 artifact has one non-retried clean native match and an
  ongoing native rebuild/compare/attest path that attests the same file.
- QEMU remains valuable and explicit for portable PR validation but is never
  mislabeled as the native qualification evidence.
- No untrusted pull-request job can reach the ARM32 runner, no persistent runner
  or credential remains, and mismatching artifacts remain `Not verified`.

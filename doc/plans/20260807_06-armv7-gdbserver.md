# Plan: Add the ARMv7 GDBserver Recipe and Binary

## Summary

Add GNU GDBserver 16.3 as a reproducible static ARMv7 executable. Port the
existing AArch64 full-system validation design to a pinned ARMv7 Alpine kernel
and QEMU's 32-bit `virt` machine so the recipe proves a real Remote Serial
Protocol exchange rather than relying on user-mode emulation.

## Problem

GDBserver is distributed for AArch64 and x86-64 but not ARMv7. Its functional
test cannot be reduced to `--version`: QEMU user mode does not reliably service
the ptrace/asynchronous behavior needed for a real inferior, so ARMv7 needs a
tool-owned full-system validation path.

## Scope

In scope:

- Add `recipes/gdbserver/armv7/` with tracked GNU GDB 16.3 source and PGP
  evidence, the existing GDBserver-only feature profile, licenses, link
  inventory, and ARMv7 smoke helpers.
- Pin and checksum an official HTTPS ARMv7 Alpine `vmlinuz-virt` in a tool-owned
  `vm.lock`; cache the kernel outside the repository and boot a generated
  diskless initramfs with `qemu-system-arm`.
- Commit the validated ARMv7 GDBserver and its catalog, checksum, README, and
  TRUST records.

Out of scope:

- Building the GDB client, in-process agent, binutils, Python, Guile, or other
  disabled GDB components.
- Committing a kernel or VM disk, sharing VM machinery with another recipe, or
  modifying existing GDBserver recipes.
- Adding an independent rebuild service or provenance attestation.

## Design

Port the AArch64 recipe ownership directly. Preserve the GNU-signed source,
GDBserver-only configure switches, `-all-static` final link, exact archive
inventory, and small PID 1/RSP/target helpers. Translate the compiler triplet
and archive paths to values verified in the locked ARMv7 builder.

Use the official ARMv7 Alpine virt kernel selected during implementation with
a literal HTTPS URL, release, filename, SHA-256, and explicit authentication
mode. Boot it with `qemu-system-arm -machine virt,highmem=off -cpu cortex-a15`,
the generated initramfs, PL011 console, no network or disk, and a bounded
timeout. The smoke test must attach GDBserver to a real ARMv7 target, observe a
valid stop reply, process the kill packet, and shut down cleanly. A failure may
reuse the preserved build output but must not trigger another compilation
merely to retry the test.

Apply the ARMv7 artifact checks to GDBserver and both static helpers: ELF32,
little-endian ARM, hard-float EABI, `ET_EXEC`, no interpreter, no `DT_NEEDED`,
stripped release output, exact version, and native execution inside the VM.
The cached kernel is validation infrastructure only and is not linked or
distributed. Record the maintainer-built recipe validation and the absence of
independent rebuild evidence as separate TRUST facts.

## Affected Components

- `recipes/gdbserver/armv7/*`: add the source/evidence, build, full-system VM
  definition, smoke helpers, licenses, and link inventory.
- `artifacts/armv7/gdbserver`: add the validated executable.
- `recipes/catalog.tsv`: enable the ARMv7 identity.
- `artifacts/SHA256SUMS`: add its sorted exact digest.
- `README.md`: list ARMv7 GDBserver and rebuild support.
- `TRUST.md`: record GNU PGP authentication, the VM kernel limitation, the
  local recipe build, and the absence of independent rebuild evidence.

## Implementation Sequence

1. Require the adopted ARMv7 r2 builder and resolve one official ARMv7 virt
   kernel that boots QEMU `virt`; pin its exact bytes before recipe execution.
2. Port the recipe and helpers, establish exact ARMv7 archive ownership, and
   run syntax and C warning checks before compilation.
3. Tell the user the expected emulated compile duration when it may exceed ten
   minutes. Build once and preserve its BuildKit output before running the
   kernel/version/RSP validations.
4. Add the artifact and shared live records only after the VM reports the
   success marker. Stage explicit paths, validate, commit, and push.

## Validation

- Verify the tracked GDB archive and detached signature offline with the exact
  pinned GNU fingerprint through `python3 scripts/recipes.py validate`.
- Run shell syntax and C warning checks, `./validate.sh`, and
  `git diff --check`.
- Run `./build.sh gdbserver armv7`; require one verified kernel download/cache,
  exact version output, complete static link inventory, and the bounded VM RSP
  exchange.
- Inspect GDBserver and smoke helpers with `file`/`readelf`, then verify the
  installed artifact checksum and complete manifest.
- Confirm local validation does not compile the utility, create a utility
  image, or add an independent attestation claim.

## Success Criteria

- The committed binary is a stripped static ARMv7 hard-float GDBserver built
  from the authenticated tracked source.
- Its full-system ARMv7 smoke test proves a real inferior attach, stop reply,
  kill exchange, and clean shutdown using only declarative cached VM inputs.
- Existing GDBserver recipes and artifacts remain byte-for-byte unchanged.

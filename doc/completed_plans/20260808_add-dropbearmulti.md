# Plan: Add Dropbear SSH Across Ready Architectures

## Summary

Add Dropbear 2026.94 as one static `dropbearmulti` executable for `aarch64`,
`armv7`, `x86`, and `x86_64`. The single artifact will directly dispatch the
SSH server, client, key generator, and key converter without repository-owned
symlinks or wrappers, and every target will pass a real loopback public-key SSH
session before its artifact is installed.

## Problem

The repository has rsync and general networking tools but no encrypted remote
shell. Users must currently supply an external SSH command, which is awkward on
recovery systems where these static artifacts are most useful.

Adding only Dropbear's server or client would leave half of that workflow
missing. Shipping separate copies would duplicate most code, while publishing
the upstream multi-call binary under the name `dropbear` would make normal
basename dispatch select the server and obscure the other roles. The recipe
also needs to distinguish features implemented inside the binary from SFTP,
shells, account data, and other runtime facilities supplied by the host.

## Scope

In scope:

- Add `artifacts/<architecture>/dropbearmulti` and one enabled recipe for each
  of the four ready architectures.
- Build the upstream `dropbear`, `dbclient`, `dropbearkey`, and
  `dropbearconvert` programs into one multi-call executable. Support direct
  subcommands `dropbear`, `dbclient`/`ssh`, `dropbearkey`/`ssh-keygen`, and
  `dropbearconvert`.
- Keep Dropbear's current modern server/client authentication, forwarding, key,
  cipher, MAC, and key-exchange defaults, including Ed25519 and post-quantum
  hybrid key exchange, while pinning the intentional omissions.
- Prove server, client, key-generation, key-conversion, public-key
  authentication, SSH negotiation, re-execution, and remote-command behavior
  on every promised target architecture.
- Preserve the signed source, applicable component licenses, final-link
  inventory, checksum manifest, catalog, and trust records.

Out of scope:

- OpenSSH, PAM, X11 forwarding, zlib compression, SFTP, `scp`, an SFTP helper,
  a daemon service, init script, system user, default host keys, or persistent
  configuration/state.
- Repository-owned `ssh`, `dropbear`, or `ssh-keygen` symlinks; copied binaries,
  shell wrappers, utility runtime images, or a generic multi-call dispatcher.
- Changing rsync behavior or its recipes. The Dropbear recipe may document
  `rsync -e '/path/to/dropbearmulti dbclient'`, but rsync already accepts a
  separately supplied remote shell.
- Builder publication, catalog/schema changes, generic recipe refactoring,
  root README changes, architecture-policy changes, native qualification, or
  an exact-rebuild/attestation claim.

## Design

Use the official HTTPS `dropbear-2026.94.tar.bz2` release archive, published
2026-07-23, with accepted size 2,386,978 bytes and SHA-256
`e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81`.
Track the detached `.asc` signature and an export-minimal keyring made from
upstream's official 2015 signing-key file. Declare `pgp` authentication and
require the RSA/SHA-512 signature's exact full fingerprint
`F7347EF2EE2E07A267628CA944931494F29C6773`; normal builds must verify only the
tracked archive, signature, and keyring and must perform no network fetch.

Configure with `--enable-static`, `--enable-bundled-libtom`, and
`--disable-zlib`. Build with
`PROGRAMS="dropbear dbclient dropbearkey dropbearconvert" MULTI=1`, so the only
exported result is `dropbearmulti`; do not build `scp`. Commit a minimal
`localoptions.h` that disables `DROPBEAR_SFTPSERVER`, because upstream SFTP
support merely executes an external helper that this repository will not
provide. Leave other feature defaults from the pinned release intact rather
than copying and maintaining the full upstream options header. Validate the
selected surface through multi-call help, server/client `-Q` output, and real
behavior, including representative modern algorithms and the absence of
disabled SHA-1-era/CBC choices.

Use the source-bundled libtomcrypt and libtommath implementations instead of
allowing builder packages to select the crypto backend. Compile with
`-O2 -pipe`; on x86 apply `-march=i686 -msse2 -mfpmath=sse` to Dropbear and all
bundled library objects. Record a final linker map and reconcile every linked
static archive exactly against package, version, license text, and source
evidence. The current locked builders already provide the compiler, musl
headers/runtime, and static `crypt()` support, so the recipe must not resolve a
new package set or modify a builder.

Select static PIE for all four recipes. A direct probe of every committed
builder digest shows that its normal `cc -static` result is `ET_DYN`; enforce
that profile rather than adding `-no-pie`. Before and after installation,
require the exact machine, ELF class, endianness, ABI, nonzero entry point,
executable `PT_LOAD`, `DF_1_PIE`, no `PT_INTERP`, no `DT_NEEDED`, no text
relocations, and stripped state. Preserve the ARMv7 ELF32/little-endian/EABI5
hard-float checks and the x86 i686/CMOV/SSE2 baseline.

Retain and review the release's consolidated `LICENSE`, the bundled
libtomcrypt and libtommath license files, and license/source evidence for musl,
GCC runtime archives, and every other input actually observed in the final
link. The recipe README must distinguish the included SSH implementation from
runtime host requirements: a valid user database and shell, writable key and
known-host locations as needed, entropy, networking, and kernel facilities for
requested forwarding or PTYs. It must say that password authentication is
compiled in but PAM, compression, SFTP, SCP, and X11 are absent, and repeat
upstream's warning that `dropbearconvert` should process only trusted key files.

The target smoke test first requires the exact 2026.94 version, exact enabled
multi-call roles, no `scp` role, and the intended algorithm profile. In a
bounded temporary directory it then:

1. Generates Ed25519 host and client keys with the candidate's
   `dropbearkey` role and derives the client's authorized-key line.
2. Converts the client key Dropbear to OpenSSH and back with
   `dropbearconvert`, then verifies that the round-tripped public key is
   unchanged.
3. Starts the same candidate as a foreground server bound only to an
   unprivileged loopback port, with explicit host key, authorized-key
   directory, pid/log paths, and password authentication disabled at runtime.
4. Runs the same candidate as `dbclient`, accepts only the temporary test host
   key non-interactively, authenticates as the container's root account using
   the generated key, executes a deterministic shell command, and requires its
   exact output.

Use bounded readiness polling, client/server timeouts, a cleanup trap, and
captured diagnostics. Run in an isolated target container with no external
network dependency. This proves the multi-call re-exec path and both sides of
an SSH session under native execution or the architecture's supported
Buildx/QEMU user-mode emulation; no full VM or native hardware is required.

Each host entry point follows the existing candidate-first Buildx flow: check
Buildx before setup, use only the architecture's committed builder digest,
export to temporary storage, validate and target-run the candidate, replace
the conventional artifact only after success, revalidate the installed file,
and require candidate/installed hash equality.

## Affected Components

- `recipes/dropbearmulti/{aarch64,armv7,x86,x86_64}/`: add Dockerfiles,
  host/guest build scripts, minimal feature overrides, ELF and functional smoke
  tests, READMEs, PGP source locks and tracked inputs, and exact license/link
  inventories.
- `recipes/catalog.tsv`: add four enabled `dropbearmulti` rows.
- `artifacts/{aarch64,armv7,x86,x86_64}/dropbearmulti`: add four validated
  regular executable artifacts.
- `artifacts/SHA256SUMS`: add four sorted exact checksum records.
- `TRUST.md`: add four Dropbear 2026.94 upstream-PGP source records with the
  exact signer fingerprint; add no independent artifact evidence.

No generic scripts, builders, architecture documentation, rsync recipe,
workflow, or root README should change because the rollout conforms to current
repository contracts.

## Implementation Sequence

1. Re-fetch the release archive, signature, and officially published key into
   temporary storage; verify HTTPS provenance, accepted checksum and size,
   exact fingerprint/signature, release version/date, and all relevant license
   texts before committing identical mode-`100644` inputs to each recipe.
2. Implement and really build x86-64 first. Lock the configure result,
   multi-call role/algorithm assertions, actual link-map inventory, static-PIE
   validator, key round trip, and loopback SSH test before copying the recipe
   shape.
3. Add AArch64, ARMv7, and x86 recipes with the same source, feature override,
   programs, and smoke behavior; vary only OCI platform/triplet, target/ABI
   validation, inventory paths, and the explicit x86 compilation baseline.
4. Warn that the remaining emulated builds may exceed ten minutes and provide
   a rough estimate. Run each build once through its committed builder digest,
   reuse BuildKit cache for late validation retries, and keep only candidates
   that pass all source, link, ELF, key, and SSH-session checks.
5. Inspect artifact sizes and hosting limits, then add all four catalog rows
   and artifacts atomically, update the checksum manifest and `TRUST.md`, and
   audit the source/license path for every distributed file.
6. Run focused and full repository validation, explicitly stage only this
   rollout, move this plan to `doc/completed_plans/` with execution notes, and
   commit and push without the unrelated in-progress objdump work.

## Validation

- Run `bash -n` on host scripts, `sh -n` on guest/smoke/ELF scripts,
  `git diff --check`, and inspect tracked input/executable modes before an
  expensive build.
- Verify each archive SHA-256 and its detached RSA/SHA-512 signature using only
  the tracked minimal keyring; require the exact full fingerprint and fail
  closed before extraction.
- Require the configure/build logs and target output to identify Dropbear
  2026.94, bundled libtomcrypt/libtommath, static/no-zlib mode, exactly the four
  selected program roles, no `scp`, and no external SFTP helper.
- Reconcile the final link map one-to-one with reviewed source and license
  evidence for every source-built and builder-owned archive; reject missing and
  surplus inventory rows.
- Validate every candidate and installed output as a stripped static PIE for
  its exact target with no interpreter, dynamic dependency, or text relocation;
  enforce ARMv7 hard-float and x86 i686/CMOV/SSE2 details.
- On all four targets, run version/role/algorithm checks, the Ed25519 key
  generation and Dropbear/OpenSSH conversion round trip, and a real isolated
  public-key SSH remote-command session using the candidate as both server and
  client.
- Require installed/candidate hash equality, then run
  `python3 scripts/recipes.py validate`,
  `sha256sum -c artifacts/SHA256SUMS`, and `./validate.sh`.
- Confirm `./build.sh list` shows exactly four `dropbearmulti` pairs and no
  symlink/wrapper, `scp`, SFTP helper, service state, runtime image, builder,
  generic dispatcher, rsync change, workflow change, or unsupported trust
  claim entered the diff.

## Success Criteria

- `./build.sh dropbearmulti <architecture>` rebuilds each committed artifact
  solely from the tracked signed 2026.94 source and existing immutable builder.
- Every artifact is a stripped static PIE for its promised host architecture
  and directly exposes server, client, keygen, and key-conversion subcommands.
- Each target passes a real key-based loopback SSH command using the artifact on
  both ends, plus functional key generation/conversion and feature-surface
  checks.
- Users get a practical SSH remote shell for recovery and rsync transport with
  clear runtime requirements and honest omissions, without four duplicate
  executables or repository-owned aliases.
- Source authentication, component licenses, linked-input provenance, catalog,
  checksums, and trust records are complete for all ready architectures, with
  no unrelated infrastructure or assurance change.

## Execution Notes

Completed on 2026-08-08 by implementation commit
`549b36c4f0fa485466e5fdcb7d02fe1a99a424d7`.

Implemented Dropbear 2026.94 as one independently rebuildable `dropbearmulti`
artifact for each ready architecture. Every recipe consumes its architecture's
committed immutable builder, verifies the tracked release archive and detached
RSA/SHA-512 signature against the exact
`F7347EF2EE2E07A267628CA944931494F29C6773` fingerprint, builds only the four
planned roles, reconciles the final link map with reviewed source/license
evidence, and validates a temporary candidate before artifact installation.

All four target smoke tests passed under the supported native or Buildx/QEMU
execution path. They verify the exact role and algorithm surface, generate
Ed25519 host and client keys, round-trip the client key through OpenSSH format,
and run a bounded public-key-authenticated loopback SSH command with the same
candidate serving both ends. Password authentication is disabled for that
test, and no `scp` or external SFTP role is present.

Committed artifact results:

- `aarch64`: 528,096 bytes,
  `cb9d9b3e8ab9f7c144843125ea1b669b5e9337ed63efbd1949c04c4d6e54aebf`
- `armv7`: 362,844 bytes,
  `c754656d9d75d985f558f361014aefed6710bc4e6a6e151e117c2f3dee164828`
- `x86`: 608,680 bytes,
  `cd88adb4c9f6fcbae4070edd199ef140e390fe6afe9f92a0920ddd259ad07730`
- `x86_64`: 561,048 bytes,
  `ec67a38033ce3de5507a45de7378b2c94c5c18580cd11496095ebd1977d5dc26`

Each artifact passed the exact machine, class, endianness, ABI, static-PIE,
stripping, no-interpreter, no-`DT_NEEDED`, and no-text-relocation checks.
ARMv7 additionally passed EABI5 hard-float validation, and x86 was compiled and
validated against the required i686/SSE2 baseline. Candidate and installed
hashes matched for every architecture.

Validation also passed for all host/guest script syntax, all four tracked
source checksums and signatures, `python3 scripts/recipes.py validate` (60
enabled recipes), `sha256sum -c artifacts/SHA256SUMS`, `./build.sh list`,
`git diff --check`, and `./validate.sh` (60 enabled recipes and 25 repository
tests).

There were no material plan deviations. Trailing whitespace was normalized in
the separately extracted license-text copies to satisfy repository diff
hygiene; the signed tracked source archives remain byte-exact. No unresolved
blocker or deliberately excluded follow-up remains within this plan's scope.

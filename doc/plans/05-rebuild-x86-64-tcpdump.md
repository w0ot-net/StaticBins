# Plan: Rebuild x86-64 tcpdump as a Locked Recipe

## Summary

Replace only the legacy x86-64 tcpdump artifact with a stripped, validated
binary built by one non-interactive command from the committed x86-64 builder
digest and two checksum-locked upstream archives. Preserve tcpdump 4.99.4 and
libpcap 1.10.4 to avoid combining provenance repair with a version upgrade.
Publish the recipe through the manifest-driven interface established by the
preceding plans and remove the relocated legacy script once the conforming
recipe replaces it.

This plan assumes the GDB source-lock and manifest plans and
`doc/completed_plans/20260806_04-lock-x64-build-environment.md` are complete.

## Problem

`recipes/tcpdump/x86_64/legacy.sh` is an interactive root-only Alpine script
that runs `apk update`, installs mutable packages, downloads unchecked source
archives, rewrites a generated Makefile, and writes its results under `/opt`
and `/tmp` instead of replacing `artifacts/x86_64/tcpdump`. Its linkage checks can print
dynamic dependencies without necessarily failing. The committed tcpdump is a
static x86-64 executable reporting tcpdump 4.99.4 and libpcap 1.10.4, but it is
not stripped and the repository cannot demonstrate that the script produced
those exact bytes or provide the notices for the code linked into them.

## Scope

In scope:

- Pin tcpdump 4.99.4 and libpcap 1.10.4 source metadata in one tool-owned lock,
  including approved HTTPS upstream and immutable repository-mirror URLs,
  archive names, SHA-256 checksums, versions, and licenses.
- Publish both verified source archives through the immutable source-mirror
  process established for GDB, making only the bounded extension needed for a
  recipe with two archives.
- Replace the monolithic legacy implementation with a tool-owned Dockerfile,
  guest build script, and host build command that consume the committed x86_64
  builder digest without package installation or fallback.
- Build libpcap from its locked archive, link tcpdump statically using supported
  configure switches, strip the result, and validate the temporary artifact
  before replacing `artifacts/x86_64/tcpdump`.
- Remove `recipes/tcpdump/x86_64/legacy.sh` when the conforming recipe takes
  ownership; old deep implementation paths are not public interfaces.
- Preserve the intentional small-feature profile: no runtime OpenSSL crypto,
  libcap-ng, libsmi, D-Bus, Bluetooth, USB capture, RDMA, or libnl dependency.
- Commit upstream notices and a factual inventory for every archive included in
  the final static link, and distribute them in the tcpdump artifact image.
- Add tcpdump to the recipe catalog and artifact publication matrix with the
  fixed x86_64 architecture/platform/native-runner mapping.
- Update the concise user documentation and replace the committed binary after
  all target-architecture, static-link, version, and focused tcpdump tests pass.

Out of scope:

- Migrating or modifying `artifacts/x86_64/gdbserver`, `artifacts/x86_64/lsof`,
  `artifacts/x86_64/socat`, or `artifacts/x86_64/strace`.
- Upgrading tcpdump, libpcap, Alpine, or the locked builder while repairing the
  recipe.
- Preserving the current tcpdump bytes, debug sections, build ID, or an
  undocumented configure option that the 1.10.4 configure script does not
  support.
- Adding OpenSSL, libcap-ng, libsmi, hardware-specific capture dependencies, or
  a broad privileged integration-test environment.
- Generalizing tool-specific configure, license-inventory, or functional-test
  logic into a plugin framework.
- Byte-for-byte reproducibility, Alpine repository mirroring, or migration of a
  second x86-64 artifact.

## Design

Create `recipes/tcpdump/x86_64/` as the recipe owner. Its shell-
readable `source.lock` records both accepted inputs. Preserve the source bytes
currently named by the legacy script:

- `tcpdump-4.99.4.tar.gz`, SHA-256
  `0232231bb2f29d6bf2426e70a08a7e0c63a0d59a9b44863b7f5e2357a6e49fea`.
- `libpcap-1.10.4.tar.gz`, SHA-256
  `ed19a0383fad72e3ad435fd239d7cd80d64916b87269550159d20e47160ebe5f`.

The source-mirror maintainer path downloads each official tcpdump.org archive
to a new temporary file, verifies the corresponding locked checksum, refuses
an existing release/tag/asset, and publishes both archives plus reviewed source
metadata and notices in one immutable release. A normal build tries the mirror
and official URL for each archive independently but accepts bytes only after
the one locked checksum matches. Failure of every approved URL, or mismatched
bytes from any URL, fails closed before extraction. Keep the two-source handling
within the existing source-mirror owner; do not introduce a general dependency
resolver.

`build-in-container.sh` assumes the exact builder from
`builders/x86_64/environment.lock`, verifies its required commands and
static libc input, and never invokes `apk`. It builds libpcap into a private
prefix with shared libraries and unneeded optional capture backends disabled,
then configures tcpdump against that prefix with crypto, libcap-ng, and libsmi
disabled. Use only switches accepted by the pinned configure scripts and pass
static include/link settings through their supported configure variables. Link
with explicit `-static -no-pie` policy so the output contract is ELF `ET_EXEC`,
and delete the legacy generated-Makefile rewrite. Honor `BUILD_JOBS` without
allowing version or checksum overrides to bypass `source.lock`.

The guest script installs and strips only `/out/tcpdump`, then fails unless
`file` and `readelf` identify an x86-64 ELF `ET_EXEC` executable with no
requested program interpreter and no `DT_NEEDED` entries. Capture the verbose
final link or a linker map during implementation
without committing a build log. Reconcile every linked project or external
archive with the tcpdump source, libpcap source, or an exact package in the
locked builder. Commit the applicable upstream license texts and a concise
`NOTICE.md` with authoritative source/package locations; an unmapped archive or
missing required notice blocks artifact replacement and publication.

`build.sh` follows the proven GDB host contract with `linux/amd64`: check Docker,
verify or register amd64 execution with the locked binfmt image when needed,
pull exactly `BUILDER_IMAGE`, build into a narrowly scoped temporary directory,
and never fall back to Alpine or resolve packages. Support both Buildx local
output and direct execution of the locked builder so native hosts without
Buildx retain a one-command path. Run all validation against the temporary
output before installing it as `artifacts/x86_64/tcpdump`; a failed build must leave the
previous committed artifact intact. Report the installed file's size and
SHA-256.

The focused smoke test runs on linux/amd64 using a locked runtime image. In
addition to `--version`, compile a representative BPF expression and decode a
small generated packet-capture fixture with deterministic, name-resolution-free
output. Add a short bounded loopback capture with only the Docker capabilities
needed for packet capture if the native CI environment supports it reliably;
the offline filter/decode test remains the required non-privileged functional
test.

Add one enabled `tcpdump\tx86_64\ttrue` row to the minimal catalog and reuse its
existing `linux/amd64`, x86-64 builder-lock, and native-runner derivations.
Reuse the root dispatcher and generic artifact workflow; do not add another
tcpdump-specific publication workflow. Publish a scratch image containing
`/tcpdump` and the license directory with `4.99.4-x86_64` and
`x86_64-latest` tags, repository linkage, cache, SBOM, and provenance. Delete
the relocated legacy script as part of the atomic recipe replacement.

## Affected Components

- `recipes/tcpdump/x86_64/legacy.sh`: remove the obsolete interactive
  implementation when the conforming files replace it.
- `recipes/tcpdump/x86_64/source.lock`: own both source versions,
  filenames, hashes, approved URLs, immutable mirror metadata, and licenses.
- `recipes/tcpdump/x86_64/build.sh`: provide the one-command locked
  build, target validation, smoke tests, and final artifact installation.
- `recipes/tcpdump/x86_64/build-in-container.sh`: perform the
  dependency-free guest build, strip, linked-input inspection, and static ELF
  checks.
- `recipes/tcpdump/x86_64/Dockerfile`: build from the required x86_64
  builder digest and package the binary plus notices in a scratch image.
- `recipes/tcpdump/x86_64/licenses/*`: preserve upstream licenses and
  the reviewed linked-input/source/package inventory.
- `.github/workflows/mirror-sources.yml`: extend the immutable mirror operation
  delivered by the GDB source plan for the bounded two-archive tcpdump input.
- `recipes/catalog.tsv`: add only the enabled `tcpdump`/`x86_64` allowlist row;
  version, paths, image, tags, cache, platform, and runner remain derived.
- `scripts/recipes.py` and `tests/test_recipes.py`: retain the existing bounded
  x86-64 mapping and add only validation needed for tcpdump's two-source lock,
  if the current generic material checks do not already cover it.
- `.github/workflows/publish-containers.yml`: remain generic and consume the
  already-derived tcpdump matrix entry without a tool-specific branch.
- `artifacts/x86_64/tcpdump`: replace the unstripped legacy artifact with the exact
  validated recipe output.
- `README.md`, `recipes/tcpdump/x86_64/README.md`, and
  `doc/adding-a-binary.md`: mark tcpdump rebuild support complete and document
  the root/direct commands, pinned versions, output, source mirror/notices, and
  intentional feature omissions.

## Implementation Sequence

1. Add the two-source lock with the verified upstream checksums above, copy and
   review the upstream license texts, and determine the immutable mirror release
   name and asset URLs without changing the artifact.
2. Make the bounded source-mirror workflow extension, publish both verified
   archives and distribution metadata once, and anonymously verify every mirror
   asset against both the lock and a fresh official download.
3. Add the Dockerfile and guest script. Build libpcap and tcpdump using only
   supported source-level switches, capture the final static link inputs, and
   complete the license/source inventory before accepting `/out/tcpdump`.
4. Add the host command and delete the relocated legacy script. Exercise both
   the Buildx path when available and the direct locked-builder path, ensuring
   failures do not replace `artifacts/x86_64/tcpdump`.
5. Add the three-field catalog row, then validate root dispatch, direct
   dispatch, derived image metadata, and native-runner publication.
6. Run a clean one-command rebuild, compare the candidate's reported features
   with the documented intended profile, complete all static and functional
   checks, confirm the binary size is suitable for repository hosting, and only
   then replace `artifacts/x86_64/tcpdump`.
7. Update the bounded user/onboarding documentation, publish the artifact
   image, and anonymously pull and execute both its versioned and floating tags.

## Validation

- Run Bash syntax checks on both host entry points, `sh -n` on the guest script,
  the recipe-catalog unit tests and validator, workflow YAML parsing,
  ShellCheck when available, and `git diff --check`.
- Verify `source.lock` has exactly two distinct archive records with the pinned
  versions and SHA-256 values above. Download each immutable mirror asset and
  official archive anonymously, compare their hashes, exercise each approved
  URL as the sole available source, and confirm corrupted content fails before
  extraction.
- Search the normal build path to confirm it contains no `apk`, mutable image
  fallback, interactive prompt, absolute persistent build directory, generated
  Makefile rewrite, or caller override for locked source acceptance.
- Run the new direct command and root dispatcher in a controlled test; confirm
  dispatch selects the conventional recipe and propagates a forced failure.
  Run `./build.sh tcpdump` from a fresh checkout as the full supported build.
- Before installation and again on `artifacts/x86_64/tcpdump`, use `file` and `readelf`
  to verify x86-64 ELF `ET_EXEC`, no requested interpreter, no `DT_NEEDED`
  entries, and no retained debug or full symbol-table sections.
- Run `tcpdump --version` on linux/amd64 and assert tcpdump 4.99.4 and libpcap
  1.10.4. Compile a BPF expression and decode the generated pcap fixture,
  checking stable protocol/address/port output; run the bounded live-loopback
  check when the environment supports the declared capabilities.
- Reconcile the captured final link against `licenses/NOTICE.md`, inspect the
  scratch image for every committed notice, and fail on an archive without a
  source/package/license mapping.
- Run the catalog-driven publication on its native x86-64 runner, then
  anonymously pull both tcpdump tags, inspect OCI architecture/source/license
  metadata plus SBOM/provenance, and repeat the version and offline decode test
  against the published image.
- Confirm the four other `artifacts/x86_64/` files and all AArch64 artifacts, recipes,
  catalog rows, and published tags are unchanged.

## Success Criteria

- `./build.sh tcpdump` and `./recipes/tcpdump/x86_64/build.sh` rebuild the
  expected artifact through one exact public x86-64 builder digest and
  checksum-locked source inputs without package resolution or interaction;
  `legacy.sh` is gone.
- The installed `artifacts/x86_64/tcpdump` is a stripped static x86-64 executable,
  reports tcpdump 4.99.4 with libpcap 1.10.4, and passes deterministic filter
  compilation and offline packet decoding on the target architecture.
- Both source archives are available from immutable repository mirrors and
  remain byte-identical to the approved upstream archives.
- The repository and artifact image contain a complete factual source,
  package, and license inventory for the final static link.
- Catalog-driven native publication produces versioned and floating x86_64 image
  tags with the required repository metadata, SBOM, and provenance.
- No other legacy binary is rebuilt, modified, documented as reproducible, or
  added to the publication catalog by this migration.

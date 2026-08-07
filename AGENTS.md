# Agent Guidance

This repository is `static_bins`. Its purpose is to distribute useful static
binaries together with the smallest practical, documented, repeatable process
for rebuilding each one.

Repository contract:

- A committed binary must have a corresponding committed build script. Do not
  add binaries of unknown origin or binaries that can only be rebuilt by hand.
- Put binaries in `artifacts/<architecture>/`, tool builds in
  `recipes/<tool>/<architecture>/`, and reusable build environments in
  `builders/<architecture>/`. Internal architecture identifiers are `aarch64`
  and `x86_64`; translate them to OCI names only at container boundaries.
- Keep a tool's container definition, guest-side build script, patches, tracked
  source archives, source lock, licenses, and host-side entry point together in
  its recipe directory.
- Prefer one obvious host-side command per artifact. It should create or replace
  the expected file in `artifacts/<architecture>/` and fail with a useful
  message if prerequisites or validation are missing.
- Treat an architecture label as a promise about the executable's host
  architecture, not merely the kind of code it can inspect or process. For
  example, `artifacts/aarch64/gdb` must itself execute on AArch64 Linux.
- Preserve existing artifacts and build paths unless the task explicitly
  replaces or removes them.
- Every reproducible recipe must have one valid `recipes/catalog.tsv` row. Keep
  only its name, architecture, and enabled state there; treat the
  `(name, architecture)` pair as its identity and derive conventional
  paths from repository layout and validate source versions from recipe locks.
  Keep source, configure, license, and smoke-test logic in the tool-owned
  recipe. Follow `doc/adding-a-binary.md` and run
  `python3 scripts/recipes.py validate` when a recipe or catalog field changes.
- Keep `artifacts/SHA256SUMS` complete and exact for every distributed file,
  excluding the manifest itself. Record every artifact in `TRUST.md` as either
  `Exact rebuild + GitHub attestation` or `Not verified`; checksums and source
  authentication alone do not establish artifact provenance.

Reproducible build guidance:

- Prefer a minimal Alpine container over a full VM. Native builds are ideal;
  Docker/QEMU user-mode emulation is acceptable for non-native architectures.
- If a full VM is genuinely required, commit a declarative VM definition and
  provisioning/build scripts, not a VM disk image. Pin and verify any downloaded
  base image, and arrange for the final artifact to be copied back to the repo.
- Pin the upstream source version and verify its checksum before extraction.
  Declare each source's authentication mode explicitly. For `pgp`, verify the
  tracked detached signature with a tracked minimal keyring and exact full
  fingerprint; for `checksum-only`, report the weaker assurance without
  treating it as a fallback after failed authentication. Use HTTPS upstream
  provenance and fail closed on verification errors.
- Pin the build-environment version and immutable image digest when practical.
  Record relevant source, environment, dependency, and output versions. Do not
  claim byte-for-byte reproducibility unless it has actually been demonstrated;
  the primary requirement is that a fresh checkout can repeat the build.
- A normal artifact build must consume the committed builder digest from the
  architecture's environment lock. Do not silently fall back to a mutable tag,
  base image, or fresh package resolution when that digest is unavailable.
- Docker Buildx is the only supported host-side container build backend. Check
  for it before emulation registration, image pulls, temporary output creation,
  or compilation, and fail with an actionable error when it is missing. Do not
  select direct guest-script execution or classic `docker build` as a fallback.
- Treat builder publication as a separate maintainer operation: validate and
  publish a new versioned builder first, then commit its immutable digest before
  recipes may consume it.
- Give each reproducible recipe one committed source lock and keep every
  required archive and authentication evidence under its `sources/` directory.
  During a reviewed source update, download from the recorded official HTTPS
  URL into temporary storage, verify the proposed checksum and declared
  authentication, inspect the size against hosting limits, then commit the exact
  files with mode `100644`. Normal builds must use only those tracked archive
  bytes, verify them before extraction, and must not publish source-only
  repository releases.
- Keep reviewed license text and a factual linked-input provenance inventory
  with each recipe. The build must fail when the final link contains an
  archive that is missing package, version, license, or source evidence.
- Keep unreviewed downloads, package caches, object files, container layers,
  and VM scratch state outside the tracked tree. Reviewed recipe inputs under
  `sources/` are the deliberate exception. Use a narrowly scoped temporary or
  cache directory and clean it safely.
- Prefer source-level configure switches over Makefile rewriting or ad hoc
  binary patching. Document intentionally omitted features, especially Python,
  plugins, runtime data, or libraries that users might reasonably expect.
- Keep scripts non-interactive and fail-fast (`set -eu` or `set -euo pipefail`).
  Allow simple environment-variable overrides for expensive settings such as
  parallel build jobs without weakening pinned-source verification by default.

Static artifact validation:

- Building with `-static` is not proof. Use `file` plus `readelf` and fail if the
  ELF has a requested program interpreter or any `DT_NEEDED` entries.
- Verify the exact ELF machine/architecture and executable type expected by the
  destination directory.
- Run a smoke test on the target architecture, either natively or through the
  same emulation used for the build. For command-line programs, at minimum run
  the version command; add a focused functional test when that would catch
  likely static-link or runtime-data failures.
- Strip release binaries unless debug symbols in the tool itself are part of
  the artifact's purpose. Report the final size and SHA-256 checksum.
- When changing a build, rebuild and validate its artifact. Do not assume script
  review alone proves that the checked-in binary matches the recipe.
- Add an artifact to the attestation workflow only after one clean native build
  reproduces its committed bytes exactly. The attestation job must rebuild,
  compare, and attest the same file in one job. Do not retry a qualification
  mismatch or automatically grant attested status to new catalog rows.

Documentation and distribution:

- Distribute utilities only as committed executables under `artifacts/`. GHCR
  is reserved for reusable builder environments; recipe Dockerfiles export
  local build results and must not define or publish utility runtime images.
- Keep `README.md` concise and task-oriented. Document the one-command build,
  prerequisites, output path, pinned upstream version, important feature
  tradeoffs, and any host-wide setup such as `binfmt_misc` registration.
- Preserve upstream license and copyright requirements. Before distributing a
  new binary, identify its license and ensure the repository or linked release
  process provides whatever source, notices, or written offer the license
  requires.
- Do not commit secrets, private package credentials, personal paths, build
  logs, cores, or unrelated test outputs.
- Code and scripts should remain ASCII unless a file already uses another
  character set or the change clearly requires it.
- Adding a conforming tool must not require copying or specializing the recipe
  validation workflow. Extend the architecture allowlist only when genuinely
  adding support for a new architecture.

Validation efficiency:

- Start with syntax checks and `git diff --check`, then run the narrowest real
  build and target-architecture smoke test that prove the change.
- Do not repeat a known-good expensive compilation merely to re-run a late
  validation step. Preserve the build tree and diagnostic artifacts needed to
  retry that step, or move the retry to a native/cacheable builder.
- Design late-stage validation to report all discovered mismatches in one pass.
  When a failure still requires a rebuild, reuse a valid cache and avoid slow
  emulation unless the emulated path itself is what must be tested.
- Compilation under emulation can be slow. Before a validation expected to take
  more than 10 minutes, tell the user what will run and give a rough estimate.
- Avoid rebuilding unrelated binaries or running broad validation when only one
  artifact changed.

Git workflow:

- `main` is protected by the `artifact-trust-main` ruleset. Send code,
  documentation, recipe, workflow, and binary changes through a pull request;
  do not disable or bypass the ruleset for convenience.
- Preserve the required check names `recipe-validation` and
  `artifact-assurance`. Both must report on every pull request, while the latter
  may skip expensive builds when no artifact trust boundary changed.
- Pin every GitHub Actions `uses:` reference to a full 40-character commit SHA.
  Repository Actions policy enforces this invariant.
- Always commit, push, and merge through the protected path after code,
  documentation, recipe, or binary changes.
- Never use `git add .` or `git add -A`; stage explicit paths only.
- Commit only files touched for the task and preserve unrelated user changes.
- Before committing a large binary, confirm it is the intended validated output
  and inspect repository hosting limits.

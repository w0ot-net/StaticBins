# Agent Guidance

This repository is `static_bins`. Its purpose is to distribute useful static
binaries together with the smallest practical, documented, repeatable process
for rebuilding each one.

Repository contract:

- A committed binary must have a corresponding committed build script. Do not
  add binaries of unknown origin or binaries that can only be rebuilt by hand.
- Put binaries in `<architecture>_bins/` and build automation in
  `<architecture>_alpine_build_scripts/`. Keep a tool's container definition,
  guest-side build script, patches, and host-side entry point together in one
  tool-named directory when more than one file is needed.
- Prefer one obvious host-side command per artifact. It should create or replace
  the expected file in `<architecture>_bins/` and fail with a useful message if
  prerequisites or validation are missing.
- Treat an architecture label as a promise about the executable's host
  architecture, not merely the kind of code it can inspect or process. For
  example, `aarch64_bins/gdb` must itself execute on AArch64 Linux.
- Preserve existing artifacts and build paths unless the task explicitly
  replaces or removes them.
- Every publishable recipe must have one valid `recipes.tsv` row. Keep generic
  dispatch and publication metadata there; keep source, configure, license, and
  smoke-test logic in the tool-owned recipe directory. Follow
  `doc/adding-a-binary.md` and run `python3 scripts/recipes.py validate` when a
  recipe or catalog field changes.

Reproducible build guidance:

- Prefer a minimal Alpine container over a full VM. Native builds are ideal;
  Docker/QEMU user-mode emulation is acceptable for non-native architectures.
- If a full VM is genuinely required, commit a declarative VM definition and
  provisioning/build scripts, not a VM disk image. Pin and verify any downloaded
  base image, and arrange for the final artifact to be copied back to the repo.
- Pin the upstream source version and verify its checksum or signature before
  extraction. Use HTTPS upstream sources and fail closed on verification errors.
- Pin the build-environment version and immutable image digest when practical.
  Record relevant source, environment, dependency, and output versions. Do not
  claim byte-for-byte reproducibility unless it has actually been demonstrated;
  the primary requirement is that a fresh checkout can repeat the build.
- A normal artifact build must consume the committed builder digest from the
  architecture's environment lock. Do not silently fall back to a mutable tag,
  base image, or fresh package resolution when that digest is unavailable.
- Treat builder publication as a separate maintainer operation: validate and
  publish a new versioned builder first, then commit its immutable digest before
  recipes may consume it.
- Give each published recipe one committed source lock. Mirror every required
  source archive to a non-replaceable repository release asset, retain the
  official upstream as a checksum-equivalent fallback, and accept bytes only
  after verifying the locked checksum.
- Keep reviewed license text and a factual linked-input provenance inventory
  with each recipe. Publication must fail when the final link contains an
  archive that is missing package, version, license, or source evidence.
- Keep downloaded source, package caches, object files, container layers, and VM
  scratch state outside the tracked tree. Use a narrowly scoped temporary or
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

Documentation and distribution:

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
- Adding a conforming published tool must not require copying or specializing
  the container publication workflow. Extend an architecture/runner allowlist
  only when genuinely adding support for a new architecture.

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

- Always commit and push after code, documentation, recipe, or binary changes.
- Never use `git add .` or `git add -A`; stage explicit paths only.
- Commit only files touched for the task and preserve unrelated user changes.
- Before committing a large binary, confirm it is the intended validated output
  and inspect repository hosting limits.

# Build pipeline

This page owns the supported execution sequence for an ordinary artifact
build. Return to the [architecture index](../README.md).

1. The root dispatcher validates the catalog and selects one enabled
   `(name, architecture)` recipe.
2. The recipe host script requires Docker Buildx before any emulation
   registration, image pull, temporary output creation, or compilation.
3. The host loads the architecture's `environment.lock`, checks container
   execution, registers only the pinned binfmt helper when necessary, and pulls
   the exact `BUILDER_IMAGE` digest.
4. The recipe Dockerfile runs through Buildx for the target OCI platform and
   exports its final file to a narrowly scoped temporary directory.
5. The guest script verifies the tracked source checksum before extraction,
   configures and builds the selected feature profile, reconciles the final
   static link with its archive inventory, strips the release output, and runs
   guest-side checks.
6. The host checks the temporary candidate's expected ELF machine, class,
   endianness where relevant, executable type, lack of interpreter and
   `DT_NEEDED` entries, and stripped state. It then runs the recipe's
   target-architecture version and functional smoke tests.
7. Only a fully validated candidate is installed at mode `0755`. The host
   revalidates the installed file and requires its SHA-256 to equal the
   candidate before reporting size and checksum.

Failure before installation leaves the committed artifact untouched. Temporary
state is cleaned narrowly; expensive BuildKit caches and intentional diagnostic
outputs may be retained outside the tracked tree for a bounded retry.

This path is distinct from `python3 scripts/recipes.py validate`. The validator
checks repository structure, tracked evidence, authentication, locks, modes,
and artifact-manifest consistency without compiling. A build independently
rechecks the bytes it consumes and the executable it produces.

Docker Buildx is the only host-side build backend. There is no direct guest
execution or classic `docker build` fallback, and a recipe must not resolve a
replacement builder or packages when its committed digest is unavailable.

Related authorities: [source inputs](SOURCE_INPUTS.md),
[build environments](BUILD_ENVIRONMENTS.md), and the
[artifact contract](../artifacts/ARTIFACT_CONTRACT.md).

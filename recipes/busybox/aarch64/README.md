# Static BusyBox 1.38.0 for AArch64

From the repository root, run:

```sh
./build.sh busybox aarch64
```

The command requires Bash, Docker, Docker Buildx, `file`, `readelf`, and
`sha256sum`. It consumes the immutable AArch64 builder lock and
replaces `artifacts/aarch64/busybox` only after complete validation.

BusyBox 1.38.0 is upstream's latest published source release and is labeled
unstable upstream. This recipe deliberately uses that exact checksum-only
release; no authenticated signer key has been adopted. The executable is a
multi-call toolbox, not a root filesystem or installed applet symlink farm.
Invoke tools as `busybox <applet>`, or create links separately after reviewing
their effects.

The committed `busybox.config` is the complete resolved static defconfig.
`expected-applets.txt` is the exact 407-applet runtime contract. The broad
profile includes shells, file/text/process utilities, archive and checksum
tools, and networking/system applets. The `tc` applet is the sole defconfig
omission because its legacy CBQ code is incompatible with the locked builder's
Linux 7.0 UAPI headers. Some enabled applets still require privileges, kernel
features, device nodes, or external runtime files such as user databases,
certificates, locales, and configuration files.

The build uses the documented aarch64 compiler baseline, reconciles every
source-built and builder-provided archive with license/source evidence, and
selects the locked toolchain's stripped static PIE `ET_DYN` profile without
an interpreter, shared dependency, or text relocation. The tracked source
archive alongside the recipe supplies the corresponding BusyBox source under
GPL-2.0-only; bundled bzip2 and permissive component notices remain in that
source and are documented under `licenses/`.

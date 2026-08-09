# Static BusyBox 1.38.0 for 32-bit x86

From the repository root, run:

```sh
./build.sh busybox x86
```

The command requires Bash, Docker, Docker Buildx, `file`, `readelf`, and
`sha256sum`. It consumes the immutable 32-bit x86 builder lock and
replaces `artifacts/x86/busybox` only after complete validation.

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

The x86 profile also disables the optional SHA-1/SHA-256 hardware accelerator:
BusyBox's 32-bit SHA-NI assembly contains read-only relocations that cannot be
linked into static PIE. The checksum applets and software implementations
remain enabled, so applet membership and behavior stay aligned with the other
architectures.

The build uses the documented x86 compiler baseline, reconciles every
source-built and builder-provided archive with license/source evidence, and
selects the locked toolchain's stripped static PIE `ET_DYN` profile without
an interpreter, shared dependency, or text relocation. The tracked source
archive alongside the recipe supplies the corresponding BusyBox source under
GPL-2.0-only; bundled bzip2 and permissive component notices remain in that
source and are documented under `licenses/`.

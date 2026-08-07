# Static lsof 4.99.5 for x86-64

From the repository root, run:

```sh
./build.sh lsof x86_64
```

The command requires Bash, Docker, and Docker Buildx. It consumes the immutable
x86-64 builder in `builders/x86_64/environment.lock` and replaces
`artifacts/x86_64/lsof` only after validation.

The recipe uses the tracked, checksum-locked lsof 4.99.5 release archive. No
detached upstream signature has been adopted, so source authentication is
explicitly `checksum-only`. The native static build retains Linux IPv6, task,
endpoint, socket-state, and libtirpc RPC support, disables SELinux and the
separate liblsof output, and applies no setuid or setgid mode.

Validation requires a stripped static x86-64 `ET_EXEC`, exact version and
feature output, complete final-link evidence, and successful procfs discovery
of a uniquely named file held open by a controlled process.

Source, linked archive, and license evidence are documented in `source.lock`
and `licenses/`.

# Static Dropbear 2026.94 for 32-bit x86

From the repository root, run:

```sh
./build.sh dropbearmulti x86
```

The command requires Bash, Docker, Docker Buildx, `file`, `gpgv`, `readelf`,
and `sha256sum`. It consumes the immutable 32-bit x86 builder in
`builders/x86/environment.lock` and replaces
`artifacts/x86/dropbearmulti` only after complete validation.

The recipe verifies the tracked official Dropbear 2026.94 archive and detached
RSA/SHA-512 signature with an export-minimal keyring pinned to fingerprint
`F7347EF2EE2E07A267628CA944931494F29C6773`. Normal builds perform no network
fetching or package resolution.

This one multi-call executable provides the Dropbear server, `dbclient`/`ssh`
client, `dropbearkey`/`ssh-keygen`, and `dropbearconvert`. Invoke a role as a
subcommand, for example:

```sh
./artifacts/x86/dropbearmulti ssh user@example.com
rsync -e './artifacts/x86/dropbearmulti dbclient' source/ host:dest/
```

The build uses the bundled libtomcrypt and libtommath code and retains the
pinned release's modern algorithm profile, public-key/password authentication,
agent forwarding, and TCP forwarding. PAM, X11, zlib compression, SFTP, and
SCP are omitted. `dropbearconvert` is intended only for trusted key files; its
upstream parser is not safe for untrusted input.

The executable does not provide a service definition, users, host keys,
authorized keys, known-host state, a shell, an SFTP helper, or persistent
configuration. Server use requires suitable account databases and shells;
requested PTYs and forwarding also require the corresponding host kernel and
device support.

The output is a stripped x86 ELF32 static PIE with an i686/CMOV/SSE2 baseline and no interpreter, shared
dependencies, or text relocations. The target smoke test uses the artifact as
both server and client for a real loopback public-key SSH command and also
tests Ed25519 key generation and Dropbear/OpenSSH key conversion.

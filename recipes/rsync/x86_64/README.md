# Static rsync 3.4.4 for x86-64

From the repository root, run:

```sh
./build.sh rsync x86_64
```

The command requires Bash, Docker, Docker Buildx, `file`, `gpgv`, `readelf`,
and `sha256sum`. It consumes the immutable x86-64 builder in
`builders/x86_64/environment.lock` and replaces `artifacts/x86_64/rsync` only
after complete validation.

The recipe verifies the tracked official rsync 3.4.4 archive and detached
RSA/SHA-512 signature with an export-minimal keyring pinned to Andrew
Tridgell's full fingerprint
`9FEF112DCE19A0DC7E882CB81BB24997A8535F6F`. Normal builds perform no network
fetching or generated-source regeneration.

This is protocol-32 rsync with IPv6, xattrs, daemon mode, bundled popt option
parsing, and bundled zlib compression. ACLs, iconv, OpenSSL acceleration,
xxHash, zstd, lz4, and manpage regeneration are disabled. The build validates
those capability choices and the exact bundled popt/zlib object inputs. It
does not bundle `ssh`: remote-shell transfers require a separately supplied
command, while `rsync://` daemon transfers work directly.

The output is a stripped x86-64 static PIE with no interpreter, shared
dependencies, or text relocations. Source, bundled-input, linked-archive, and
license evidence is contained in this recipe. No daemon service, default
configuration, password file, certificate, wrapper, or manpage is installed.

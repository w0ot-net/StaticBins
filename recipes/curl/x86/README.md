# Static curl 8.21.0 for x86

From the repository root, run:

```sh
./build.sh curl x86
```

The command requires Bash, Docker, Docker Buildx, `file`, `gpgv`, `readelf`,
and `sha256sum`. It automatically pulls the public immutable x86 builder
recorded in `builders/x86/environment.lock`; it fetches no source or build
packages. The artifact is replaced only after complete validation.

This deliberately focused curl supports `file`, HTTP, and HTTPS URLs with
IPv4/IPv6, proxies, cookies, Unix sockets, asynchronous DNS, and LibreSSL TLS.
FTP, mail protocols, LDAP, SMB, MQTT, Telnet, TFTP, WebSockets, SSH protocols,
HTTP/2, HTTP/3, IDN, PSL, Brotli, and Zstandard are omitted.

The default CA bundle path is `/etc/ssl/certs/ca-certificates.crt`. A target
without that file must provide trust anchors with `--cacert`, `CURL_CA_BUNDLE`,
or `SSL_CERT_FILE`. No CA bundle is embedded, so the binary does not freeze a
stale trust store into the artifact.

The output is a stripped 32-bit x86 static PIE with no interpreter, shared
dependencies, or text relocations and uses the repository's i686/SSE2
baseline. Its target smoke test verifies rejection of
an untrusted certificate and a successful loopback HTTPS transfer when the
temporary test CA is supplied explicitly.

# Static netstat 2.10 for AArch64

From the repository root, run:

```sh
./build.sh netstat aarch64
```

The command requires Bash, Docker, Docker Buildx, `file`, `readelf`, and
`sha256sum`. It consumes the immutable AArch64 builder in
`builders/aarch64/environment.lock` and replaces `artifacts/aarch64/netstat`
only after complete validation.

This standalone netstat comes from the tracked net-tools 2.10 release archive.
The release bytes use checksum-only authentication because no detached
release-file signature with authenticated full-fingerprint key evidence is
available. A separately checksum-locked patch from Alpine corrects the
nonstandard `%Lu` interface-counter parsing; its immutable aports revision and
upstream discussion are recorded in `patches/patch.lock`.

The exact noninteractive config enables Unix sockets, IPv4, IPv6, Ethernet,
and loopback reporting. I18N, SELinux, masquerade reporting, legacy non-IP
families and hardware types, and every optional net-tools program are disabled.
The build invokes only the `netstat` target and distributes no `ifconfig`,
`route`, `arp`, or other companion executable.

Upstream describes net-tools as generally deprecated and recommends iproute2
for most current use. This artifact retains the familiar netstat interface for
numeric socket, route, interface, Unix-socket, and protocol-statistics views;
some views depend on Linux procfs and permissions. It is independent of the
BusyBox netstat applet.

The output is a stripped AArch64 static PIE with no interpreter, shared
dependencies, or text relocations. Source, configuration, patch,
linked-archive, and license evidence is contained in this recipe.

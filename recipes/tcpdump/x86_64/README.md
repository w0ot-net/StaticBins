# x86-64 tcpdump recipe

This recipe builds tcpdump 4.99.4 with libpcap 1.10.4 as a stripped static
x86-64 executable. From the repository root, use the stable dispatcher or the
direct recipe command:

```sh
./build.sh tcpdump
./recipes/tcpdump/x86_64/build.sh
```

Both commands require Bash, Docker with the Buildx plugin, and access to the
public images named by the committed environment lock. The build consumes the
exact builder digest in `builders/x86_64/environment.lock` and both tracked
archives under `sources/`, validates a temporary candidate, and writes
`artifacts/x86_64/tcpdump` only after every check passes. On non-x86-64 Linux
hosts it may register the pinned
QEMU `binfmt_misc` helper with `--privileged` when amd64 container support is
absent. Set `BUILD_JOBS` to tune compilation parallelism:

```sh
BUILD_JOBS=4 ./build.sh tcpdump
```

`source.lock` owns both source versions, archive names, checksums, official
provenance URLs, and license identifiers. The accepted source copies are
committed under `sources/` and checksum-verified before extraction; a normal
build does not download them. Reviewed license material and the exact
linked-archive provenance inventory are under `licenses/` and are checked
against the final static link.

With `gpgv` installed, `python3 scripts/recipes.py validate` verifies both
committed detached signatures offline against the Tcpdump Group fingerprint
`1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D`. The signatures use RSA/SHA-512;
[`TRUST.md`](../../../TRUST.md) describes the source assurance model.

The build rejects an ELF interpreter, dynamic dependencies, a wrong machine,
retained debug or full symbol-table sections, and an incomplete linked-archive
inventory. Its smoke test checks the reported tcpdump/libpcap versions, compiles
a BPF filter, and decodes a deterministic packet capture without network access.

To keep the executable self-contained, tcpdump omits OpenSSL or LibreSSL,
libcap-ng, libsmi, and Capsicum integration. libpcap omits remote capture, USB,
netmap, Bluetooth, D-Bus, RDMA, libnl, DAG, Septel, SNF, TurboCap, and DPDK
backends.

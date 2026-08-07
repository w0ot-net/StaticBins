#!/bin/sh

set -eu

: "${GDB_VERSION:?GDB_VERSION must be set}"
: "${GDB_SHA256:?GDB_SHA256 must be set}"
: "${BUILD_JOBS:=8}"

source_archive="gdb-${GDB_VERSION}.tar.xz"
source_url="https://ftp.gnu.org/gnu/gdb/${source_archive}"
source_dir="/build/gdb-${GDB_VERSION}"
build_dir="/build/gdb-build"

for command_name in cc c++ make wget tar sha256sum file readelf strip; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done

for archive_path in \
    /usr/lib/libc.a \
    /usr/lib/libexpat.a \
    /usr/lib/libgmp.a \
    /usr/lib/libmpfr.a \
    /usr/lib/libncursesw.a \
    /usr/lib/liblzma.a \
    /usr/lib/libz.a \
    /usr/lib/libzstd.a; do
    if [ ! -f "${archive_path}" ]; then
        echo "error: locked builder is missing ${archive_path}" >&2
        exit 1
    fi
done

mkdir -p /build /out
cd /build

wget -q "${source_url}"
echo "${GDB_SHA256}  ${source_archive}" | sha256sum -c -
tar -xf "${source_archive}"
mkdir -p "${build_dir}"
cd "${build_dir}"

CFLAGS="-O2 -pipe" \
CXXFLAGS="-O2 -pipe" \
LDFLAGS="-static" \
LIBS="-lm -pthread" \
"${source_dir}/configure" \
    --build=aarch64-alpine-linux-musl \
    --host=aarch64-alpine-linux-musl \
    --target=aarch64-alpine-linux-musl \
    --prefix=/usr \
    --disable-binutils \
    --disable-gas \
    --disable-gold \
    --disable-gprof \
    --disable-ld \
    --disable-nls \
    --disable-shared \
    --disable-sim \
    --disable-source-highlight \
    --disable-werror \
    --enable-static \
    --with-curses \
    --with-expat \
    --with-libexpat-type=static \
    --with-system-zlib \
    --with-liblzma-type=static \
    --with-lzma \
    --with-zstd \
    --without-babeltrace \
    --without-debuginfod \
    --without-guile \
    --without-intel-pt \
    --without-python

make -j"${BUILD_JOBS}" all-gdb

# GDB links through GNU libtool. In libtool, -static only selects static
# libtool archives; -all-static is what passes -static to the compiler driver.
rm -f gdb/gdb
make -C gdb LDFLAGS="-all-static" gdb

install -m 0755 gdb/gdb /out/gdb
strip /out/gdb

file /out/gdb

if ! readelf -h /out/gdb | grep -Eq 'Machine:[[:space:]]+AArch64'; then
    echo "error: GDB is not an AArch64 executable" >&2
    readelf -h /out/gdb >&2
    exit 1
fi

if readelf -l /out/gdb | grep -q 'Requesting program interpreter'; then
    echo "error: GDB has a dynamic program interpreter" >&2
    exit 1
fi

if readelf -d /out/gdb 2>/dev/null | grep -q '(NEEDED)'; then
    echo "error: GDB has dynamic library dependencies" >&2
    readelf -d /out/gdb | grep '(NEEDED)' >&2
    exit 1
fi

/out/gdb --batch --version

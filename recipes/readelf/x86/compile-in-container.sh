#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

recipe_root=/usr/local/share/static_bins/binutils
source_lock="${recipe_root}/source.lock"
target_lock="${recipe_root}/target.lock"
source_input_dir="${recipe_root}/sources"

# shellcheck source=source.lock
. "${source_lock}"
# shellcheck source=target.lock
. "${target_lock}"

: "${SOURCE_VERSION:?missing SOURCE_VERSION}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256}"
: "${TARGET_TRIPLET:?missing TARGET_TRIPLET}"
: "${TARGET_CFLAGS:?missing TARGET_CFLAGS}"

for command_name in ar cc cp make sha256sum tar; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done

source_dir="/build/binutils-${SOURCE_VERSION}"
build_dir=/build/binutils-build
source_archive="/build/${SOURCE_ARCHIVE}"
mkdir -p /build /out
cp "${source_input_dir}/${SOURCE_ARCHIVE}" "${source_archive}"
printf '%s  %s\n' "${SOURCE_SHA256}" "${source_archive}" | sha256sum -c -
tar -xf "${source_archive}" -C /build
mkdir -p "${build_dir}"
cd "${build_dir}"

if ! CFLAGS="${TARGET_CFLAGS}" CXXFLAGS="${TARGET_CFLAGS}" LDFLAGS=-static \
    "${source_dir}/configure" \
        --build="${TARGET_TRIPLET}" \
        --host="${TARGET_TRIPLET}" \
        --target="${TARGET_TRIPLET}" \
        --prefix=/usr \
        --disable-gas \
        --disable-gdb \
        --disable-gdbserver \
        --disable-gold \
        --disable-gprof \
        --disable-gprofng \
        --disable-ld \
        --disable-libctf \
        --disable-multilib \
        --disable-nls \
        --disable-plugins \
        --disable-shared \
        --disable-sim \
        --disable-werror \
        --enable-static \
        --with-system-zlib \
        --with-zstd \
        --without-debuginfod \
        --without-jansson > /out/binutils-configure.log 2>&1; then
    tail -n 200 /out/binutils-configure.log >&2
    exit 1
fi
tail -n 20 /out/binutils-configure.log

if ! make -j"${BUILD_JOBS}" all-binutils > /out/binutils-build.log 2>&1; then
    tail -n 240 /out/binutils-build.log >&2
    exit 1
fi
tail -n 20 /out/binutils-build.log

cc ${TARGET_CFLAGS} -O0 -g -fno-inline -fno-omit-frame-pointer \
    -c "${recipe_root}/fixture.c" -o /out/fixture.o
cc ${TARGET_CFLAGS} -O0 -g -fno-inline -fno-omit-frame-pointer \
    -static -no-pie "${recipe_root}/fixture.c" \
    -Wl,--unresolved-symbols=ignore-all -o /out/fixture
cc ${TARGET_CFLAGS} -O0 -g -c "${recipe_root}/archive-member.c" \
    -o /out/archive-member.o
ar crs /out/libfixture.a /out/archive-member.o

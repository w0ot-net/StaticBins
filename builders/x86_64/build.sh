#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ENVIRONMENT_LOCK="${SCRIPT_DIR}/environment.lock"
readonly PACKAGE_LOCK="${SCRIPT_DIR}/packages.lock"
readonly PLATFORM="linux/amd64"

# shellcheck source=environment.lock
. "${ENVIRONMENT_LOCK}"

: "${ALPINE_IMAGE:?missing ALPINE_IMAGE in environment.lock}"
: "${BINFMT_IMAGE:?missing BINFMT_IMAGE in environment.lock}"
: "${BUILDER_TAG:?missing BUILDER_TAG in environment.lock}"

readonly ALPINE_IMAGE BINFMT_IMAGE BUILDER_TAG
readonly LOCAL_IMAGE="static_bins-builder:${BUILDER_TAG}-candidate"

case "${ALPINE_IMAGE}" in
    *@sha256:*) ;;
    *)
        echo "error: ALPINE_IMAGE must be pinned by digest" >&2
        exit 1
        ;;
esac

case "${BINFMT_IMAGE}" in
    *@sha256:*) ;;
    *)
        echo "error: BINFMT_IMAGE must be pinned by digest" >&2
        exit 1
        ;;
esac

case "${BUILDER_TAG}" in
    x64-*) ;;
    *)
        echo "error: BUILDER_TAG must begin with x64-" >&2
        exit 1
        ;;
esac

if ! command -v docker >/dev/null 2>&1; then
    echo "error: Docker is required" >&2
    exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
    echo "error: Docker Buildx is required; install the plugin and ensure 'docker buildx version' succeeds" >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "error: the Docker daemon is not available to this user" >&2
    exit 1
fi

if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" /bin/true >/dev/null 2>&1; then
    echo "Registering x86-64 QEMU emulation with binfmt_misc..."
    docker run --privileged --rm "${BINFMT_IMAGE}" --install amd64

    if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" /bin/true >/dev/null; then
        echo "error: Docker still cannot run x86-64 containers" >&2
        exit 1
    fi
fi

docker buildx build \
    --platform "${PLATFORM}" \
    --build-arg "ALPINE_IMAGE=${ALPINE_IMAGE}" \
    --load \
    --tag "${LOCAL_IMAGE}" \
    "${SCRIPT_DIR}"

docker run --rm \
    --platform "${PLATFORM}" \
    --mount "type=bind,src=${PACKAGE_LOCK},dst=/tmp/packages.lock,readonly" \
    "${LOCAL_IMAGE}" \
    /bin/sh -eu -c '
        validation_errors=0
        if [ "$(uname -m)" != x86_64 ]; then
            echo "error: candidate runtime is not x86-64" >&2
            validation_errors=$((validation_errors + 1))
        fi

        while IFS= read -r package_spec; do
            case "${package_spec}" in ""|\#*) continue ;; esac
            package_name=${package_spec%%=*}
            expected_version=${package_spec#*=}
            if ! installed_package=$(apk info -e -v "${package_name}"); then
                echo "error: candidate builder is missing package ${package_name}" >&2
                validation_errors=$((validation_errors + 1))
                continue
            fi
            installed_version=${installed_package#${package_name}-}
            if [ "${installed_version}" != "${expected_version}" ]; then
                echo "error: ${package_name}: expected ${expected_version}, found ${installed_version}" >&2
                validation_errors=$((validation_errors + 1))
            fi
        done < /tmp/packages.lock

        for command_name in \
            autoreconf automake bison cc c++ file flex libressl libtoolize make \
            makeinfo pkg-config readelf rpcgen sha256sum strip tar wget xz; do
            if ! command -v "${command_name}" >/dev/null 2>&1; then
                echo "error: candidate builder is missing ${command_name}" >&2
                validation_errors=$((validation_errors + 1))
            fi
        done

        libgcc_archive=$(cc -print-file-name=libgcc.a)
        for archive_path in \
            /usr/lib/libc.a \
            /usr/lib/libcrypto.a \
            /usr/lib/libexpat.a \
            /usr/lib/libgmp.a \
            /usr/lib/libmpfr.a \
            /usr/lib/libncursesw.a \
            /usr/lib/libssl.a \
            /usr/lib/libtirpc.a \
            /usr/lib/libtirpc-nokrb.a \
            /usr/lib/liblzma.a \
            /usr/lib/libz.a \
            /usr/lib/libzstd.a \
            "${libgcc_archive}"; do
            if [ ! -f "${archive_path}" ]; then
                echo "error: candidate builder is missing ${archive_path}" >&2
                validation_errors=$((validation_errors + 1))
            fi
        done

        if [ "${validation_errors}" -ne 0 ]; then
            exit 1
        fi

        validate_archive_metadata() {
            archive_path=$1
            expected_package=$2
            expected_license=$3
            expected_version=$(sed -n "s/^${expected_package}=//p" /tmp/packages.lock)
            if [ -z "${expected_version}" ]; then
                echo "error: no locked version for ${expected_package}" >&2
                validation_errors=$((validation_errors + 1))
                return
            fi
            installed_owner=$(apk info -W "${archive_path}" | sed "s/.* is owned by //")
            if [ "${installed_owner}" != "${expected_package}-${expected_version}" ]; then
                echo "error: ${archive_path}: expected ${expected_package}-${expected_version}, found ${installed_owner}" >&2
                validation_errors=$((validation_errors + 1))
            fi
            installed_license=$(sed -n "/^P:${expected_package}$/,/^$/s/^L://p" /lib/apk/db/installed)
            if [ "${installed_license}" != "${expected_license}" ]; then
                echo "error: ${expected_package}: expected license ${expected_license}, found ${installed_license}" >&2
                validation_errors=$((validation_errors + 1))
            fi
        }

        validate_archive_metadata /usr/lib/libexpat.a expat-static MIT
        validate_archive_metadata /usr/lib/libgmp.a gmp-static "LGPL-3.0-or-later OR GPL-2.0-or-later"
        validate_archive_metadata /usr/lib/libmpfr.a mpfr-dev LGPL-3.0-or-later
        validate_archive_metadata /usr/lib/libncursesw.a ncurses-static X11
        validate_archive_metadata /usr/lib/liblzma.a xz-static "GPL-2.0-or-later AND 0BSD AND Public-Domain AND LGPL-2.1-or-later"
        validate_archive_metadata /usr/lib/libz.a zlib-static Zlib
        validate_archive_metadata /usr/lib/libzstd.a zstd-static "BSD-3-Clause OR GPL-2.0-or-later"

        if [ "${validation_errors}" -ne 0 ]; then
            exit 1
        fi

        validate_static_probe() {
            probe=$1
            probe_errors=0
            if ! file "${probe}" | grep -q "statically linked"; then
                echo "error: ${probe} is not reported as statically linked" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if ! readelf -h "${probe}" | grep -Eq "Type:[[:space:]]+EXEC"; then
                echo "error: ${probe} is not an ELF executable" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if ! readelf -h "${probe}" | grep -Eq "Machine:[[:space:]]+Advanced Micro Devices X86-64"; then
                echo "error: ${probe} is not an x86-64 executable" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if readelf -l "${probe}" | grep -q "Requesting program interpreter"; then
                echo "error: ${probe} has a dynamic program interpreter" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if readelf -d "${probe}" 2>/dev/null | grep -q "(NEEDED)"; then
                echo "error: ${probe} has dynamic library dependencies" >&2
                probe_errors=$((probe_errors + 1))
            fi
            return "${probe_errors}"
        }

        printf "%s\n" "int main(void) { return 0; }" > /tmp/base-probe.c
        cc -static -no-pie /tmp/base-probe.c -o /tmp/base-probe

        printf "%s\n" "#include <rpc/xdr.h>" \
            "int main(void) { return xdr_int == 0; }" \
            > /tmp/tirpc-probe.c
        cc -static -no-pie $(pkg-config --cflags libtirpc-nokrb) \
            /tmp/tirpc-probe.c $(pkg-config --libs --static libtirpc-nokrb) \
            -o /tmp/tirpc-probe

        printf "%s\n" "#include <openssl/ssl.h>" \
            "int main(void) { SSL_CTX *ctx = SSL_CTX_new(TLS_method()); SSL_CTX_free(ctx); return ctx == 0; }" \
            > /tmp/libressl-probe.c
        cc -static -no-pie /tmp/libressl-probe.c -lssl -lcrypto \
            -o /tmp/libressl-probe

        printf "%s\n" "#include <expat.h>" \
            "int main(void) { XML_Parser p = XML_ParserCreate(0); XML_ParserFree(p); return p == 0; }" \
            > /tmp/expat-probe.c
        cc -static -no-pie /tmp/expat-probe.c -lexpat -o /tmp/expat-probe

        cat > /tmp/gdb-dependencies-probe.cc <<"EOF"
#include <curses.h>
#include <expat.h>
#include <gmp.h>
#include <lzma.h>
#include <mpfr.h>
#include <zlib.h>
#include <zstd.h>

int main()
{
    XML_Parser parser = XML_ParserCreate(nullptr);
    mpz_t integer;
    mpfr_t floating;
    mpz_init(integer);
    mpfr_init2(floating, 64);
    const bool versions_available =
        XML_ExpatVersion() != nullptr && gmp_version != nullptr &&
        mpfr_get_version() != nullptr && curses_version() != nullptr &&
        lzma_version_number() != 0 && zlibVersion() != nullptr &&
        ZSTD_versionNumber() != 0;
    mpfr_clear(floating);
    mpz_clear(integer);
    XML_ParserFree(parser);
    return versions_available ? 0 : 1;
}
EOF
        c++ -static -no-pie /tmp/gdb-dependencies-probe.cc \
            -lexpat -lmpfr -lgmp -lncursesw -llzma -lz -lzstd \
            -o /tmp/gdb-dependencies-probe

        for probe in \
            /tmp/base-probe /tmp/tirpc-probe /tmp/libressl-probe \
            /tmp/expat-probe /tmp/gdb-dependencies-probe; do
            if ! validate_static_probe "${probe}"; then
                validation_errors=$((validation_errors + 1))
            fi
        done
        if [ "${validation_errors}" -ne 0 ]; then
            exit 1
        fi
    '

image_architecture="$(docker image inspect "${LOCAL_IMAGE}" --format '{{.Architecture}}')"
image_source="$(docker image inspect "${LOCAL_IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.source"}}')"
image_errors=0

if [[ "${image_architecture}" != "amd64" ]]; then
    echo "error: candidate architecture is ${image_architecture}, expected amd64" >&2
    image_errors=$((image_errors + 1))
fi

if [[ "${image_source}" != "https://github.com/w0ot-net/static_bins" ]]; then
    echo "error: candidate has an unexpected OCI source label" >&2
    image_errors=$((image_errors + 1))
fi

if [[ ${image_errors} -ne 0 ]]; then
    exit 1
fi

echo "Validated local builder: ${LOCAL_IMAGE}"

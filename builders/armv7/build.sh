#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ENVIRONMENT_LOCK="${SCRIPT_DIR}/environment.lock"
readonly PACKAGE_LOCK="${SCRIPT_DIR}/packages.lock"
readonly PLATFORM="linux/arm/v7"

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
    armv7-*) ;;
    *)
        echo "error: BUILDER_TAG must begin with armv7-" >&2
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
    echo "Registering ARM QEMU emulation with binfmt_misc..."
    docker run --privileged --rm "${BINFMT_IMAGE}" --install arm

    if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" /bin/true >/dev/null; then
        echo "error: Docker still cannot run ARMv7 containers" >&2
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
        # BEGIN ARMV7 BUILDER VALIDATION
        validation_errors=0
        if [ "$(uname -m)" != armv7l ]; then
            echo "error: candidate runtime is not ARMv7" >&2
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
            autoconf automake autoreconf bison cc c++ file flex \
            libressl-openssl libtoolize make makeinfo perl pkg-config \
            readelf readlink rpcgen sha256sum strip tar xz; do
            if ! command -v "${command_name}" >/dev/null 2>&1; then
                echo "error: candidate builder is missing ${command_name}" >&2
                validation_errors=$((validation_errors + 1))
            fi
        done

        libgcc_archive=$(readlink -f "$(cc -print-file-name=libgcc.a)")
        libgcc_eh_archive=$(readlink -f "$(cc -print-file-name=libgcc_eh.a)")
        libstdcxx_archive=$(readlink -f "$(c++ -print-file-name=libstdc++.a)")

        validate_archive_owner() {
            archive_path=$1
            expected_owner=$2
            expected_version=$3
            if [ ! -f "${archive_path}" ]; then
                echo "error: candidate builder is missing ${archive_path}" >&2
                validation_errors=$((validation_errors + 1))
                return
            fi
            observed_owner=$(apk info --who-owns "${archive_path}" 2>/dev/null || true)
            expected_record="${archive_path} is owned by ${expected_owner}-${expected_version}"
            if [ "${observed_owner}" != "${expected_record}" ]; then
                echo "error: ${archive_path}: expected ${expected_owner}-${expected_version}, found ${observed_owner:-no owner}" >&2
                validation_errors=$((validation_errors + 1))
            fi
        }

        for archive_path in \
            /usr/lib/libc.a \
            /usr/lib/libdl.a \
            /usr/lib/libm.a \
            /usr/lib/libpthread.a \
            /usr/lib/librt.a \
            /usr/lib/libssp_nonshared.a \
            /usr/lib/libutil.a; do
            validate_archive_owner "${archive_path}" musl-dev 1.2.6-r2
        done
        validate_archive_owner /usr/lib/libcrypto.a libressl-static 4.3.1-r0
        validate_archive_owner /usr/lib/libexpat.a expat-static 2.8.2-r0
        validate_archive_owner /usr/lib/libgmp.a gmp-static 6.3.0-r4
        validate_archive_owner /usr/lib/liblzma.a xz-static 5.8.3-r0
        validate_archive_owner /usr/lib/libmpfr.a mpfr-dev 4.2.2-r0
        validate_archive_owner /usr/lib/libncursesw.a ncurses-static 6.6_p20260516-r0
        validate_archive_owner /usr/lib/libssl.a libressl-static 4.3.1-r0
        validate_archive_owner /usr/lib/libtirpc.a libtirpc-static 1.3.5-r1
        validate_archive_owner /usr/lib/libtirpc-nokrb.a libtirpc-static 1.3.5-r1
        validate_archive_owner /usr/lib/libz.a zlib-static 1.3.2-r0
        validate_archive_owner /usr/lib/libzstd.a zstd-static 1.5.7-r2
        validate_archive_owner "${libgcc_archive}" libgcc-static 15.2.0-r5
        validate_archive_owner "${libgcc_eh_archive}" gcc 15.2.0-r5
        validate_archive_owner "${libstdcxx_archive}" libstdc++-dev 15.2.0-r5

        if [ "${validation_errors}" -ne 0 ]; then
            exit 1
        fi

        validate_static_probe() {
            probe=$1
            probe_errors=0
            if ! file "${probe}" | grep -Eq "ELF 32-bit LSB executable, ARM"; then
                echo "error: ${probe} is not an ELF32 little-endian ARM executable" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if ! file "${probe}" | grep -q "statically linked"; then
                echo "error: ${probe} is not reported as statically linked" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if ! readelf -h "${probe}" | grep -Eq "Class:[[:space:]]+ELF32"; then
                echo "error: ${probe} is not ELF32" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if ! readelf -h "${probe}" | grep -Eq "Data:[[:space:]]+2.s complement, little endian"; then
                echo "error: ${probe} is not little-endian" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if ! readelf -h "${probe}" | grep -Eq "Type:[[:space:]]+EXEC"; then
                echo "error: ${probe} is not an ELF executable" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if ! readelf -h "${probe}" | grep -Eq "Machine:[[:space:]]+ARM"; then
                echo "error: ${probe} does not target ARM" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if ! readelf -h "${probe}" | grep -Eq "Flags:.*hard-float ABI"; then
                echo "error: ${probe} does not use the ARM hard-float ABI" >&2
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

        printf "%s\n" "int main(void) { return 0; }" > /tmp/c-probe.c
        cc -static -no-pie /tmp/c-probe.c -o /tmp/c-probe

        printf "%s\n" "int main() { return 0; }" > /tmp/cxx-probe.cpp
        c++ -static -no-pie /tmp/cxx-probe.cpp -o /tmp/cxx-probe

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

        cat > /tmp/gdb-libraries-probe.cpp <<"EOF"
#include <expat.h>
#include <gmp.h>
#include <lzma.h>
#include <mpfr.h>
#include <ncurses.h>
#include <zlib.h>
#include <zstd.h>

int main()
{
    XML_Parser parser = XML_ParserCreate(nullptr);
    mpz_t integer;
    mpfr_t real;
    mpz_init(integer);
    mpfr_init2(real, 64);
    const bool ok = parser != nullptr
        && curses_version() != nullptr
        && lzma_version_number() != 0
        && zlibVersion() != nullptr
        && ZSTD_versionNumber() != 0;
    XML_ParserFree(parser);
    mpfr_clear(real);
    mpz_clear(integer);
    return ok ? 0 : 1;
}
EOF
        c++ -static -no-pie /tmp/gdb-libraries-probe.cpp \
            -lexpat -lmpfr -lgmp -lncursesw -llzma -lzstd -lz -lm \
            -o /tmp/gdb-libraries-probe

        for probe in \
            /tmp/c-probe \
            /tmp/cxx-probe \
            /tmp/tirpc-probe \
            /tmp/libressl-probe \
            /tmp/expat-probe \
            /tmp/gdb-libraries-probe; do
            if ! validate_static_probe "${probe}"; then
                validation_errors=$((validation_errors + 1))
            fi
            if ! "${probe}"; then
                echo "error: ${probe} failed to execute on ARMv7" >&2
                validation_errors=$((validation_errors + 1))
            fi
        done
        if [ "${validation_errors}" -ne 0 ]; then
            exit 1
        fi
        # END ARMV7 BUILDER VALIDATION
    '

image_architecture="$(docker image inspect "${LOCAL_IMAGE}" --format '{{.Architecture}}')"
image_variant="$(docker image inspect "${LOCAL_IMAGE}" --format '{{.Variant}}')"
image_source="$(docker image inspect "${LOCAL_IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.source"}}')"
image_errors=0

if [[ "${image_architecture}" != "arm" ]]; then
    echo "error: candidate architecture is ${image_architecture}, expected arm" >&2
    image_errors=$((image_errors + 1))
fi

if [[ "${image_variant}" != "v7" ]]; then
    echo "error: candidate variant is ${image_variant}, expected v7" >&2
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

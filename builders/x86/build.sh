#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ENVIRONMENT_LOCK="${SCRIPT_DIR}/environment.lock"
readonly PACKAGE_LOCK="${SCRIPT_DIR}/packages.lock"
readonly PLATFORM="linux/386"

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
    x86-*) ;;
    *)
        echo "error: BUILDER_TAG must begin with x86-" >&2
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
    echo "Registering 32-bit x86 QEMU emulation with binfmt_misc..."
    docker run --privileged --rm "${BINFMT_IMAGE}" --install 386

    if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" /bin/true >/dev/null; then
        echo "error: Docker still cannot run 32-bit x86 containers" >&2
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
        # BEGIN 32-BIT X86 BUILDER VALIDATION
        validation_errors=0
        if [ "$(apk --print-arch)" != x86 ]; then
            echo "error: candidate package architecture is not x86" >&2
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
            objdump readelf readlink rpcgen sha256sum strip tar xz; do
            if ! command -v "${command_name}" >/dev/null 2>&1; then
                echo "error: candidate builder is missing ${command_name}" >&2
                validation_errors=$((validation_errors + 1))
            fi
        done

        if [ "${validation_errors}" -ne 0 ]; then
            exit 1
        fi

        validate_x86_elf_header() {
            elf_file=$1
            header_errors=0
            if ! file -L "${elf_file}" | grep -Eq "ELF 32-bit LSB (pie )?executable, Intel (i386|80386)"; then
                echo "error: ${elf_file} is not an ELF32 little-endian x86 executable" >&2
                header_errors=$((header_errors + 1))
            fi
            if ! readelf -h "${elf_file}" | grep -Eq "Class:[[:space:]]+ELF32"; then
                echo "error: ${elf_file} is not ELF32" >&2
                header_errors=$((header_errors + 1))
            fi
            if ! readelf -h "${elf_file}" | grep -Eq "Data:[[:space:]]+2.s complement, little endian"; then
                echo "error: ${elf_file} is not little-endian" >&2
                header_errors=$((header_errors + 1))
            fi
            if ! readelf -h "${elf_file}" | grep -Eq "Machine:[[:space:]]+Intel 80386"; then
                echo "error: ${elf_file} does not target 32-bit x86" >&2
                header_errors=$((header_errors + 1))
            fi
            return "${header_errors}"
        }

        if ! validate_x86_elf_header /bin/sh; then
            validation_errors=$((validation_errors + 1))
        fi

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
        validate_archive_owner /usr/lib/libelf.a elfutils-dev 0.195-r0
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
            if ! file "${probe}" | grep -Eq "ELF 32-bit LSB executable, Intel (i386|80386)"; then
                echo "error: ${probe} is not an ELF32 little-endian x86 executable" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if ! file "${probe}" | grep -q "statically linked"; then
                echo "error: ${probe} is not reported as statically linked" >&2
                probe_errors=$((probe_errors + 1))
            fi
            if ! validate_x86_elf_header "${probe}"; then
                probe_errors=$((probe_errors + 1))
            fi
            if ! readelf -h "${probe}" | grep -Eq "Type:[[:space:]]+EXEC"; then
                echo "error: ${probe} is not an ELF executable" >&2
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

        baseline_flags="-march=i686 -msse2 -mfpmath=sse"
        printf "\n" | cc ${baseline_flags} -dM -E - > /tmp/x86-predefines.txt
        if ! grep -Eq "^#define __i686__ 1$" /tmp/x86-predefines.txt; then
            echo "error: compiler does not report the requested i686 baseline" >&2
            validation_errors=$((validation_errors + 1))
        fi
        if ! grep -Eq "^#define __SSE2__ 1$" /tmp/x86-predefines.txt; then
            echo "error: compiler does not report the requested SSE2 baseline" >&2
            validation_errors=$((validation_errors + 1))
        fi

        cat > /tmp/c-probe.c <<"EOF"
#include <emmintrin.h>

int main(void)
{
    volatile int input = 5;
    int selected = 9;
    const int alternate = 7;
    __asm__ volatile (
        "cmpl $5, %2\n\t"
        "cmove %1, %0"
        : "+r" (selected)
        : "r" (alternate), "r" (input)
        : "cc");
    const __m128i left = _mm_set1_epi32(input);
    const __m128i right = _mm_set1_epi32(1);
    volatile int output[4];
    _mm_storeu_si128((__m128i *) (void *) output, _mm_add_epi32(left, right));
    return selected == 7 && output[0] == 6 ? 0 : 1;
}
EOF
        cc ${baseline_flags} -static -no-pie /tmp/c-probe.c -o /tmp/c-probe

        printf "%s\n" "int main() { return 0; }" > /tmp/cxx-probe.cpp
        c++ ${baseline_flags} -static -no-pie /tmp/cxx-probe.cpp -o /tmp/cxx-probe

        tirpc_cflags=$(pkg-config --cflags libtirpc-nokrb)
        tirpc_libs=$(pkg-config --libs --static libtirpc-nokrb)
        if [ "${tirpc_cflags}" != "-I/usr/include/tirpc" ]; then
            echo "error: unexpected libtirpc-nokrb CFLAGS: ${tirpc_cflags}" >&2
            validation_errors=$((validation_errors + 1))
        fi
        if [ "${tirpc_libs}" != "-ltirpc-nokrb -lpthread" ]; then
            echo "error: unexpected libtirpc-nokrb static libraries: ${tirpc_libs}" >&2
            validation_errors=$((validation_errors + 1))
        fi

        printf "%s\n" "#include <rpc/xdr.h>" \
            "int main(void) { return xdr_int == 0; }" \
            > /tmp/tirpc-probe.c
        cc ${baseline_flags} -static -no-pie ${tirpc_cflags} \
            /tmp/tirpc-probe.c ${tirpc_libs} \
            -o /tmp/tirpc-probe

        printf "%s\n" "#include <openssl/ssl.h>" \
            "int main(void) { SSL_CTX *ctx = SSL_CTX_new(TLS_method()); SSL_CTX_free(ctx); return ctx == 0; }" \
            > /tmp/libressl-probe.c
        cc ${baseline_flags} -static -no-pie /tmp/libressl-probe.c -lssl -lcrypto \
            -o /tmp/libressl-probe

        printf "%s\n" "#include <expat.h>" \
            "int main(void) { XML_Parser p = XML_ParserCreate(0); XML_ParserFree(p); return p == 0; }" \
            > /tmp/expat-probe.c
        cc ${baseline_flags} -static -no-pie /tmp/expat-probe.c -lexpat -o /tmp/expat-probe

        printf "%s\n" "#include <libelf.h>" \
            "int main(void) { return elf_version(EV_CURRENT) == EV_NONE; }" \
            > /tmp/libelf-probe.c
        cc ${baseline_flags} -static -no-pie /tmp/libelf-probe.c \
            -lelf -lzstd -lz -o /tmp/libelf-probe

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
        c++ ${baseline_flags} -static -no-pie /tmp/gdb-libraries-probe.cpp \
            -lexpat -lmpfr -lgmp -lncursesw -llzma -lzstd -lz -lm \
            -o /tmp/gdb-libraries-probe

        for probe in \
            /tmp/c-probe \
            /tmp/cxx-probe \
            /tmp/tirpc-probe \
            /tmp/libressl-probe \
            /tmp/expat-probe \
            /tmp/libelf-probe \
            /tmp/gdb-libraries-probe; do
            if ! validate_static_probe "${probe}"; then
                validation_errors=$((validation_errors + 1))
            fi
            if ! "${probe}"; then
                echo "error: ${probe} failed to execute on 32-bit x86" >&2
                validation_errors=$((validation_errors + 1))
            fi
        done
        if ! objdump -d /tmp/c-probe | grep -Eq "[[:space:]]cmov"; then
            echo "error: x86 C probe does not contain a CMOV instruction" >&2
            validation_errors=$((validation_errors + 1))
        fi
        if ! objdump -d /tmp/c-probe | grep -Eq "[[:space:]]paddd"; then
            echo "error: x86 C probe does not contain an SSE2 PADDD instruction" >&2
            validation_errors=$((validation_errors + 1))
        fi
        if [ "${validation_errors}" -ne 0 ]; then
            exit 1
        fi
        # END 32-BIT X86 BUILDER VALIDATION
    '

image_architecture="$(docker image inspect "${LOCAL_IMAGE}" --format '{{.Architecture}}')"
image_source="$(docker image inspect "${LOCAL_IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.source"}}')"
image_errors=0

if [[ "${image_architecture}" != "386" ]]; then
    echo "error: candidate architecture is ${image_architecture}, expected 386" >&2
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

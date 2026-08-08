#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ENVIRONMENT_LOCK="${SCRIPT_DIR}/environment.lock"
readonly PACKAGE_LOCK="${SCRIPT_DIR}/packages.lock"
readonly PLATFORM="linux/arm64"

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
    aarch64-*) ;;
    *)
        echo "error: BUILDER_TAG must begin with aarch64-" >&2
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
    echo "Registering ARM64 QEMU emulation with binfmt_misc..."
    docker run --privileged --rm "${BINFMT_IMAGE}" --install arm64
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
        if [ "$(uname -m)" != aarch64 ]; then
            echo "error: candidate runtime is not AArch64" >&2
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
            autoreconf automake bison cc c++ cmake file flex libtoolize make \
            libressl ninja pkg-config python3 readelf rpcgen sha256sum strip tar xz; do
            if ! command -v "${command_name}" >/dev/null 2>&1; then
                echo "error: candidate builder is missing ${command_name}" >&2
                validation_errors=$((validation_errors + 1))
            fi
        done

        libgcc_archive=$(cc -print-file-name=libgcc.a)
        for archive_path in \
            /usr/lib/libc.a \
            /usr/lib/libcrypto.a \
            /usr/lib/libelf.a \
            /usr/lib/libexpat.a \
            /usr/lib/libssl.a \
            /usr/lib/libtirpc.a \
            /usr/lib/libtirpc-nokrb.a \
            "${libgcc_archive}"; do
            if [ ! -f "${archive_path}" ]; then
                echo "error: candidate builder is missing ${archive_path}" >&2
                validation_errors=$((validation_errors + 1))
            fi
        done

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
            if ! readelf -h "${probe}" | grep -Eq "Machine:[[:space:]]+AArch64"; then
                echo "error: ${probe} is not an AArch64 executable" >&2
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

        printf "%s\n" "#include <libelf.h>" \
            "int main(void) { return elf_version(EV_CURRENT) == EV_NONE; }" \
            > /tmp/libelf-probe.c
        cc -static -no-pie /tmp/libelf-probe.c -lelf -lzstd -lz \
            -o /tmp/libelf-probe

        for probe in \
            /tmp/base-probe /tmp/tirpc-probe /tmp/libressl-probe \
            /tmp/expat-probe /tmp/libelf-probe; do
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

if [[ "${image_architecture}" != "arm64" ]]; then
    echo "error: candidate architecture is ${image_architecture}, expected arm64" >&2
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

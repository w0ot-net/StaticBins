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

        for command_name in cc c++ file make readelf strip; do
            if ! command -v "${command_name}" >/dev/null 2>&1; then
                echo "error: candidate builder is missing ${command_name}" >&2
                validation_errors=$((validation_errors + 1))
            fi
        done

        libgcc_archive=$(cc -print-file-name=libgcc.a)
        libstdcxx_archive=$(c++ -print-file-name=libstdc++.a)
        for archive_path in /usr/lib/libc.a "${libgcc_archive}" "${libstdcxx_archive}"; do
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

        for probe in /tmp/c-probe /tmp/cxx-probe; do
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

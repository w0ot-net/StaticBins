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
        test "$(uname -m)" = aarch64
        while IFS= read -r package_spec; do
            case "${package_spec}" in ""|\#*) continue ;; esac
            package_name=${package_spec%%=*}
            expected_version=${package_spec#*=}
            installed_package=$(apk info -e -v "${package_name}")
            installed_version=${installed_package#${package_name}-}
            if [ "${installed_version}" != "${expected_version}" ]; then
                echo "error: ${package_name}: expected ${expected_version}, found ${installed_version}" >&2
                exit 1
            fi
        done < /tmp/packages.lock
        for command_name in cc c++ cmake make ninja python3; do
            command -v "${command_name}" >/dev/null
        done
    '

image_architecture="$(docker image inspect "${LOCAL_IMAGE}" --format '{{.Architecture}}')"
image_source="$(docker image inspect "${LOCAL_IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.source"}}')"

if [[ "${image_architecture}" != "arm64" ]]; then
    echo "error: candidate architecture is ${image_architecture}, expected arm64" >&2
    exit 1
fi

if [[ "${image_source}" != "https://github.com/w0ot-net/static_bins" ]]; then
    echo "error: candidate has an unexpected OCI source label" >&2
    exit 1
fi

echo "Validated local builder: ${LOCAL_IMAGE}"

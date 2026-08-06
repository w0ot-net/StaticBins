#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly OUTPUT_DIR="${REPO_ROOT}/aarch64_bins"
readonly OUTPUT_FILE="${OUTPUT_DIR}/gdb"
readonly PLATFORM="linux/arm64"
readonly BUILDER_IMAGE="${BUILDER_IMAGE:-ghcr.io/w0ot-net/static_bins-builder:aarch64-alpine-3.24.1}"
readonly ALPINE_IMAGE="alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b"
readonly BINFMT_IMAGE="tonistiigi/binfmt@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0"
readonly GDB_VERSION="${GDB_VERSION:-17.2}"
readonly GDB_SHA256="${GDB_SHA256:-1c036c0d72e4b3d1fb5c94c88632add6f9d76f4d7c4d2ea793c12a9f19a3228c}"
readonly BUILD_JOBS="${BUILD_JOBS:-8}"

temporary_dir=""
build_image="${ALPINE_IMAGE}"

cleanup() {
    if [[ -n "${temporary_dir}" ]]; then
        rm -rf -- "${temporary_dir}"
    fi
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
    echo "error: Docker is required" >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "error: the Docker daemon is not available to this user" >&2
    exit 1
fi

echo "Checking ARM64 container support..."
if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" /bin/true >/dev/null 2>&1; then
    echo "Registering ARM64 QEMU emulation with binfmt_misc..."
    docker run --privileged --rm "${BINFMT_IMAGE}" --install arm64

    if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" /bin/true >/dev/null; then
        echo "error: Docker still cannot run ARM64 containers" >&2
        exit 1
    fi
fi

echo "Checking for the published reusable builder..."
if docker pull --platform "${PLATFORM}" "${BUILDER_IMAGE}"; then
    build_image="${BUILDER_IMAGE}"
else
    echo "Builder unavailable; bootstrapping from the pinned Alpine image."
fi

temporary_dir="$(mktemp -d)"
mkdir -p "${OUTPUT_DIR}"

build_args=(
    --build-arg "BUILDER_IMAGE=${build_image}"
    --build-arg "GDB_VERSION=${GDB_VERSION}"
    --build-arg "GDB_SHA256=${GDB_SHA256}"
    --build-arg "BUILD_JOBS=${BUILD_JOBS}"
)

if docker buildx version >/dev/null 2>&1; then
    echo "Building GDB ${GDB_VERSION} for ARM64 with Docker Buildx..."
    docker buildx build \
        --platform "${PLATFORM}" \
        "${build_args[@]}" \
        --output "type=local,dest=${temporary_dir}" \
        "${SCRIPT_DIR}"
else
    echo "Building GDB ${GDB_VERSION} in an ARM64 Docker container..."
    docker run --rm \
        --platform "${PLATFORM}" \
        --env "GDB_VERSION=${GDB_VERSION}" \
        --env "GDB_SHA256=${GDB_SHA256}" \
        --env "BUILD_JOBS=${BUILD_JOBS}" \
        --mount "type=bind,src=${SCRIPT_DIR}/build-in-container.sh,dst=/usr/local/bin/build-static-gdb,readonly" \
        --mount "type=bind,src=${temporary_dir},dst=/out" \
        "${build_image}" \
        /usr/local/bin/build-static-gdb
fi

install -m 0755 "${temporary_dir}/gdb" "${OUTPUT_FILE}"

echo
echo "Built ${OUTPUT_FILE}"
file "${OUTPUT_FILE}"
sha256sum "${OUTPUT_FILE}"

if command -v readelf >/dev/null 2>&1; then
    if ! readelf -h "${OUTPUT_FILE}" | grep -Eq 'Machine:[[:space:]]+AArch64'; then
        echo "error: output is not an AArch64 executable" >&2
        exit 1
    fi
    if readelf -l "${OUTPUT_FILE}" | grep -q 'Requesting program interpreter'; then
        echo "error: output has a dynamic program interpreter" >&2
        exit 1
    fi
    if readelf -d "${OUTPUT_FILE}" 2>/dev/null | grep -q '(NEEDED)'; then
        echo "error: output has dynamic library dependencies" >&2
        exit 1
    fi
fi

docker run --rm \
    --platform "${PLATFORM}" \
    --mount "type=bind,src=${OUTPUT_FILE},dst=/gdb,readonly" \
    "${ALPINE_IMAGE}" \
    /gdb --batch --version

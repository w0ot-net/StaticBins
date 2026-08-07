#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly ENVIRONMENT_LOCK="${SCRIPT_DIR}/environment.lock"
readonly PLATFORM="linux/arm64"

# shellcheck source=environment.lock
. "${ENVIRONMENT_LOCK}"

: "${ALPINE_IMAGE:?missing ALPINE_IMAGE in environment.lock}"
: "${BINFMT_IMAGE:?missing BINFMT_IMAGE in environment.lock}"
: "${BUILDER_IMAGE:?missing BUILDER_IMAGE in environment.lock}"

readonly ALPINE_IMAGE BINFMT_IMAGE BUILDER_IMAGE

if ! command -v docker >/dev/null 2>&1; then
    echo "error: Docker is required" >&2
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

if ! docker pull --platform "${PLATFORM}" "${BUILDER_IMAGE}"; then
    echo "error: could not pull ${BUILDER_IMAGE}" >&2
    echo "Publish and lock a replacement with build.sh and publish-builder.yml." >&2
    exit 1
fi

tty_args=()
if [[ -t 0 && -t 1 ]]; then
    tty_args=(-it)
fi

if (( $# == 0 )); then
    set -- /bin/bash
fi

exec docker run --rm \
    "${tty_args[@]}" \
    --platform "${PLATFORM}" \
    --mount "type=bind,src=${REPO_ROOT},dst=/workspace" \
    --workdir /workspace \
    "${BUILDER_IMAGE}" \
    "$@"

#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly PLATFORM="linux/arm64"
readonly BUILDER_IMAGE="${BUILDER_IMAGE:-ghcr.io/w0ot-net/static_bins-builder:aarch64-alpine-3.24.1}"
readonly ALPINE_IMAGE="alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b"
readonly BINFMT_IMAGE="tonistiigi/binfmt@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0"

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
    echo "The GHCR package must exist and be public, or Docker must be logged in." >&2
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

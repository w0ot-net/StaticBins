#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
readonly TARGET_LOCK="${SCRIPT_DIR}/target.lock"
readonly SOURCE_LOCK="${SCRIPT_DIR}/source.lock"

# shellcheck source=target.lock
. "${TARGET_LOCK}"
# shellcheck source=source.lock
. "${SOURCE_LOCK}"
# shellcheck source=/dev/null
. "${REPO_ROOT}/builders/${TARGET_ARCHITECTURE}/environment.lock"

: "${TARGET_ARCHITECTURE:?missing TARGET_ARCHITECTURE}"
: "${TARGET_DISPLAY:?missing TARGET_DISPLAY}"
: "${TARGET_PLATFORM:?missing TARGET_PLATFORM}"
: "${TARGET_BINFMT:?missing TARGET_BINFMT}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256}"
: "${SOURCE_AUTHENTICATION:?missing SOURCE_AUTHENTICATION}"
: "${ALPINE_IMAGE:?missing ALPINE_IMAGE}"
: "${BINFMT_IMAGE:?missing BINFMT_IMAGE}"
: "${BUILDER_IMAGE:?missing BUILDER_IMAGE}"

readonly OUTPUT_DIR="${REPO_ROOT}/artifacts/${TARGET_ARCHITECTURE}"
readonly OUTPUT_FILE="${OUTPUT_DIR}/sqlite3"
temporary_dir=""
cleanup() {
    if [[ -n "${temporary_dir}" ]]; then
        rm -rf -- "${temporary_dir}"
    fi
}
trap cleanup EXIT HUP INT TERM

for command_name in docker file readelf sha256sum; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: ${command_name} is required" >&2
        exit 1
    fi
done
if ! docker buildx version >/dev/null 2>&1; then
    echo "error: Docker Buildx is required; install the plugin and ensure 'docker buildx version' succeeds" >&2
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "error: the Docker daemon is not available to this user" >&2
    exit 1
fi
if [[ "${SOURCE_AUTHENTICATION}" != checksum-only ]]; then
    echo "error: unexpected SQLite source authentication mode: ${SOURCE_AUTHENTICATION}" >&2
    exit 1
fi

source_archive="${SCRIPT_DIR}/sources/${SOURCE_ARCHIVE}"
printf '%s  %s\n' "${SOURCE_SHA256}" "${source_archive}" | sha256sum -c -
echo "SQLite source authentication: checksum-only (official SHA3-256 recorded; no detached upstream signature)"

echo "Checking ${TARGET_DISPLAY} container support..."
if ! docker run --rm --platform "${TARGET_PLATFORM}" "${ALPINE_IMAGE}" \
    /bin/true >/dev/null 2>&1; then
    echo "Registering ${TARGET_DISPLAY} QEMU emulation with binfmt_misc..."
    docker run --privileged --rm "${BINFMT_IMAGE}" --install "${TARGET_BINFMT}"
    if ! docker run --rm --platform "${TARGET_PLATFORM}" "${ALPINE_IMAGE}" \
        /bin/true >/dev/null; then
        echo "error: Docker still cannot run ${TARGET_DISPLAY} containers" >&2
        exit 1
    fi
fi

echo "Pulling the locked reusable builder..."
if ! docker pull --platform "${TARGET_PLATFORM}" "${BUILDER_IMAGE}"; then
    echo "error: could not pull public locked builder ${BUILDER_IMAGE}" >&2
    echo "Check network access to ghcr.io and retry." >&2
    exit 1
fi

temporary_dir="$(mktemp -d)"
mkdir -p "${OUTPUT_DIR}"
echo "Building SQLite ${SOURCE_VERSION} for ${TARGET_DISPLAY} with Docker Buildx..."
docker buildx build \
    --platform "${TARGET_PLATFORM}" \
    --build-arg "BUILDER_IMAGE=${BUILDER_IMAGE}" \
    --output "type=local,dest=${temporary_dir}" \
    "${SCRIPT_DIR}"

candidate="${temporary_dir}/sqlite3"
"${SCRIPT_DIR}/validate-elf.sh" "${candidate}"
docker run --rm \
    --platform "${TARGET_PLATFORM}" \
    --network none \
    --mount "type=bind,src=${candidate},dst=/sqlite3,readonly" \
    --mount "type=bind,src=${SCRIPT_DIR}/smoke-test.sh,dst=/smoke-test,readonly" \
    "${BUILDER_IMAGE}" \
    /smoke-test /sqlite3 "${SOURCE_VERSION}"
read -r candidate_sha256 _ < <(sha256sum "${candidate}")

install -m 0755 "${candidate}" "${OUTPUT_FILE}"
"${SCRIPT_DIR}/validate-elf.sh" "${OUTPUT_FILE}"
read -r installed_sha256 _ < <(sha256sum "${OUTPUT_FILE}")
if [[ "${installed_sha256}" != "${candidate_sha256}" ]]; then
    echo "error: installed sqlite3 does not match the validated candidate" >&2
    exit 1
fi

echo
echo "Built ${OUTPUT_FILE}"
wc -c "${OUTPUT_FILE}"
sha256sum "${OUTPUT_FILE}"

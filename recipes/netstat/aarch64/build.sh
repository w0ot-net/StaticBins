#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
readonly OUTPUT_DIR="${REPO_ROOT}/artifacts/aarch64"
readonly OUTPUT_FILE="${OUTPUT_DIR}/netstat"
readonly ENVIRONMENT_LOCK="${REPO_ROOT}/builders/aarch64/environment.lock"
readonly SOURCE_LOCK="${SCRIPT_DIR}/source.lock"
readonly PATCH_LOCK="${SCRIPT_DIR}/patches/patch.lock"
readonly PLATFORM="linux/arm64"
readonly BUILD_JOBS="${BUILD_JOBS:-8}"

# shellcheck source=../../../builders/aarch64/environment.lock
. "${ENVIRONMENT_LOCK}"
: "${ALPINE_IMAGE:?missing ALPINE_IMAGE in environment.lock}"
: "${BINFMT_IMAGE:?missing BINFMT_IMAGE in environment.lock}"
: "${BUILDER_IMAGE:?missing BUILDER_IMAGE in environment.lock}"
readonly ALPINE_IMAGE BINFMT_IMAGE BUILDER_IMAGE

# shellcheck source=source.lock
. "${SOURCE_LOCK}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE in source.lock}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256 in source.lock}"
: "${SOURCE_AUTHENTICATION:?missing SOURCE_AUTHENTICATION in source.lock}"
readonly SOURCE_VERSION SOURCE_ARCHIVE SOURCE_SHA256 SOURCE_AUTHENTICATION

# shellcheck source=patches/patch.lock
. "${PATCH_LOCK}"
: "${PATCH_1:?missing PATCH_1 in patch.lock}"
: "${PATCH_1_SHA256:?missing PATCH_1_SHA256 in patch.lock}"
: "${PATCH_1_AUTHENTICATION:?missing PATCH_1_AUTHENTICATION in patch.lock}"
readonly PATCH_1 PATCH_1_SHA256 PATCH_1_AUTHENTICATION

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
if [[ "${SOURCE_AUTHENTICATION}" != checksum-only ||
    "${PATCH_1_AUTHENTICATION}" != checksum-only ]]; then
    echo "error: unexpected netstat source or patch authentication mode" >&2
    exit 1
fi

source_archive="${SCRIPT_DIR}/sources/${SOURCE_ARCHIVE}"
source_patch="${SCRIPT_DIR}/patches/${PATCH_1}"
printf '%s  %s\n' "${SOURCE_SHA256}" "${source_archive}" | sha256sum -c -
printf '%s  %s\n' "${PATCH_1_SHA256}" "${source_patch}" | sha256sum -c -
echo "source authentication: checksum-only (no detached release-file signature)"
echo "patch authentication: checksum-only (reviewed immutable Alpine aports input)"

echo "Checking AArch64 container support..."
if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" /bin/true \
    >/dev/null 2>&1; then
    echo "Registering AArch64 QEMU emulation with binfmt_misc..."
    docker run --privileged --rm "${BINFMT_IMAGE}" --install arm64
    if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" \
        /bin/true >/dev/null; then
        echo "error: Docker still cannot run AArch64 containers" >&2
        exit 1
    fi
fi

echo "Checking for the published reusable builder..."
if ! docker pull --platform "${PLATFORM}" "${BUILDER_IMAGE}"; then
    echo "error: could not pull locked builder ${BUILDER_IMAGE}" >&2
    echo "Publish with ./builders/publish.sh aarch64, then lock its reported digest." >&2
    exit 1
fi

temporary_dir="$(mktemp -d)"
mkdir -p "${OUTPUT_DIR}"

echo "Building netstat ${SOURCE_VERSION} for AArch64 with Docker Buildx..."
docker buildx build \
    --platform "${PLATFORM}" \
    --build-arg "BUILDER_IMAGE=${BUILDER_IMAGE}" \
    --build-arg "BUILD_JOBS=${BUILD_JOBS}" \
    --output "type=local,dest=${temporary_dir}" \
    "${SCRIPT_DIR}"

candidate="${temporary_dir}/netstat"
"${SCRIPT_DIR}/validate-elf.sh" "${candidate}"
docker run --rm \
    --platform "${PLATFORM}" \
    --network none \
    --mount "type=bind,src=${candidate},dst=/netstat,readonly" \
    --mount "type=bind,src=${SCRIPT_DIR}/smoke-test.sh,dst=/smoke-test,readonly" \
    "${BUILDER_IMAGE}" \
    /smoke-test /netstat "${SOURCE_VERSION}"
read -r candidate_sha256 _ < <(sha256sum "${candidate}")

install -m 0755 "${candidate}" "${OUTPUT_FILE}"
"${SCRIPT_DIR}/validate-elf.sh" "${OUTPUT_FILE}"
read -r installed_sha256 _ < <(sha256sum "${OUTPUT_FILE}")
if [[ "${installed_sha256}" != "${candidate_sha256}" ]]; then
    echo "error: installed netstat does not match the validated candidate" >&2
    exit 1
fi

echo
echo "Built ${OUTPUT_FILE}"
wc -c "${OUTPUT_FILE}"
sha256sum "${OUTPUT_FILE}"

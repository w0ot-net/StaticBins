#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
readonly SOURCE_LOCK="${SCRIPT_DIR}/source.lock"
readonly TARGET_LOCK="${SCRIPT_DIR}/target.lock"
readonly BUILD_JOBS="${BUILD_JOBS:-8}"

# shellcheck source=source.lock
. "${SOURCE_LOCK}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
readonly SOURCE_VERSION

# shellcheck source=target.lock
. "${TARGET_LOCK}"
: "${TARGET_ARCHITECTURE:?missing TARGET_ARCHITECTURE in target.lock}"
: "${TARGET_DISPLAY:?missing TARGET_DISPLAY in target.lock}"
: "${TARGET_PLATFORM:?missing TARGET_PLATFORM in target.lock}"
: "${TARGET_BINFMT:?missing TARGET_BINFMT in target.lock}"
: "${EXPECTED_MACHINE:?missing EXPECTED_MACHINE in target.lock}"
: "${EXPECTED_CLASS:?missing EXPECTED_CLASS in target.lock}"
: "${EXPECTED_DATA:?missing EXPECTED_DATA in target.lock}"
readonly TARGET_ARCHITECTURE TARGET_DISPLAY TARGET_PLATFORM TARGET_BINFMT
readonly EXPECTED_MACHINE EXPECTED_CLASS EXPECTED_DATA

readonly OUTPUT_DIR="${REPO_ROOT}/artifacts/${TARGET_ARCHITECTURE}"
readonly OUTPUT_FILE="${OUTPUT_DIR}/bpftrace"
readonly ENVIRONMENT_LOCK="${REPO_ROOT}/builders/${TARGET_ARCHITECTURE}/environment.lock"

# shellcheck source=/dev/null
. "${ENVIRONMENT_LOCK}"
: "${ALPINE_IMAGE:?missing ALPINE_IMAGE in environment.lock}"
: "${BINFMT_IMAGE:?missing BINFMT_IMAGE in environment.lock}"
: "${BUILDER_IMAGE:?missing BUILDER_IMAGE in environment.lock}"
readonly ALPINE_IMAGE BINFMT_IMAGE BUILDER_IMAGE

temporary_dir=""
cleanup() {
    if [[ -n "${temporary_dir}" ]]; then
        rm -rf -- "${temporary_dir}"
    fi
}
trap cleanup EXIT HUP INT TERM

for command_name in docker file readelf sha256sum wc; do
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

echo "Checking for the published reusable builder..."
if ! docker pull --platform "${TARGET_PLATFORM}" "${BUILDER_IMAGE}"; then
    echo "error: could not pull locked builder ${BUILDER_IMAGE}" >&2
    echo "Publish with ./builders/publish.sh ${TARGET_ARCHITECTURE}, then lock its reported digest." >&2
    exit 1
fi

temporary_dir="$(mktemp -d)"
mkdir -p "${OUTPUT_DIR}"

echo "Building bpftrace ${SOURCE_VERSION} for ${TARGET_DISPLAY} with Docker Buildx..."
docker buildx build \
    --platform "${TARGET_PLATFORM}" \
    --build-arg "BUILDER_IMAGE=${BUILDER_IMAGE}" \
    --build-arg "BUILD_JOBS=${BUILD_JOBS}" \
    --output "type=local,dest=${temporary_dir}" \
    "${SCRIPT_DIR}"

candidate="${temporary_dir}/bpftrace"
"${SCRIPT_DIR}/validate-elf.sh" \
    "${candidate}" "${EXPECTED_MACHINE}" "${EXPECTED_CLASS}" "${EXPECTED_DATA}"
candidate_size="$(wc -c < "${candidate}")"
if (( candidate_size >= 100000000 )); then
    echo "error: packed bpftrace is ${candidate_size} bytes; repository guard requires less than 100 MB" >&2
    exit 1
fi
docker run --rm \
    --privileged \
    --pid host \
    --platform "${TARGET_PLATFORM}" \
    --network none \
    --mount "type=bind,src=/sys/kernel/tracing,dst=/sys/kernel/tracing" \
    --mount "type=bind,src=${candidate},dst=/bpftrace,readonly" \
    --mount "type=bind,src=${SCRIPT_DIR}/smoke-test.sh,dst=/smoke-test,readonly" \
    "${BUILDER_IMAGE}" \
    /smoke-test /bpftrace "${SOURCE_VERSION}"
read -r candidate_sha256 _ < <(sha256sum "${candidate}")

install -m 0755 "${candidate}" "${OUTPUT_FILE}"
"${SCRIPT_DIR}/validate-elf.sh" \
    "${OUTPUT_FILE}" "${EXPECTED_MACHINE}" "${EXPECTED_CLASS}" "${EXPECTED_DATA}"
read -r installed_sha256 _ < <(sha256sum "${OUTPUT_FILE}")
if [[ "${installed_sha256}" != "${candidate_sha256}" ]]; then
    echo "error: installed bpftrace does not match the validated candidate" >&2
    exit 1
fi

echo
echo "Built ${OUTPUT_FILE}"
wc -c "${OUTPUT_FILE}"
sha256sum "${OUTPUT_FILE}"

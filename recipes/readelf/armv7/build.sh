#!/usr/bin/env bash

set -euo pipefail

readonly TOOL_NAME=readelf
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
readonly TARGET_LOCK="${SCRIPT_DIR}/target.lock"
readonly SOURCE_LOCK="${SCRIPT_DIR}/source.lock"
readonly BUILD_JOBS="${BUILD_JOBS:-8}"

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
: "${EXPECTED_MACHINE:?missing EXPECTED_MACHINE}"
: "${EXPECTED_CLASS:?missing EXPECTED_CLASS}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION}"
: "${EXPECTED_VERSION_OUTPUT:?missing EXPECTED_VERSION_OUTPUT}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256}"
: "${SOURCE_SIGNATURE:?missing SOURCE_SIGNATURE}"
: "${SOURCE_SIGNING_KEY:?missing SOURCE_SIGNING_KEY}"
: "${SOURCE_SIGNER_FINGERPRINT:?missing SOURCE_SIGNER_FINGERPRINT}"
: "${ALPINE_IMAGE:?missing ALPINE_IMAGE}"
: "${BINFMT_IMAGE:?missing BINFMT_IMAGE}"
: "${BUILDER_IMAGE:?missing BUILDER_IMAGE}"

readonly OUTPUT_DIR="${REPO_ROOT}/artifacts/${TARGET_ARCHITECTURE}"
readonly OUTPUT_FILE="${OUTPUT_DIR}/${TOOL_NAME}"
temporary_dir=""
cleanup() {
    if [[ -n "${temporary_dir}" ]]; then
        rm -rf -- "${temporary_dir}"
    fi
}
trap cleanup EXIT HUP INT TERM

for command_name in docker file gpgv readelf sha256sum; do
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

source_archive="${SCRIPT_DIR}/sources/${SOURCE_ARCHIVE}"
source_signature="${SCRIPT_DIR}/sources/${SOURCE_SIGNATURE}"
source_keyring="${SCRIPT_DIR}/sources/${SOURCE_SIGNING_KEY}"
printf '%s  %s\n' "${SOURCE_SHA256}" "${source_archive}" | sha256sum -c -
signature_status="$(gpgv --status-fd 1 --keyring "${source_keyring}" \
    "${source_signature}" "${source_archive}" 2>/dev/null)"
if ! grep -Fq "[GNUPG:] VALIDSIG ${SOURCE_SIGNER_FINGERPRINT} " \
    <<< "${signature_status}"; then
    echo "error: Binutils signature did not match the locked fingerprint" >&2
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
    echo "Publish with ./builders/publish.sh ${TARGET_ARCHITECTURE}, then lock its digest." >&2
    exit 1
fi

temporary_dir="$(mktemp -d)"
mkdir -p "${OUTPUT_DIR}"
echo "Building GNU ${TOOL_NAME} ${SOURCE_VERSION} for ${TARGET_DISPLAY} with Docker Buildx..."
docker buildx build \
    --platform "${TARGET_PLATFORM}" \
    --build-arg "BUILDER_IMAGE=${BUILDER_IMAGE}" \
    --build-arg "BUILD_JOBS=${BUILD_JOBS}" \
    --output "type=local,dest=${temporary_dir}" \
    "${SCRIPT_DIR}"

candidate="${temporary_dir}/${TOOL_NAME}"
fixture_binary="${temporary_dir}/fixture"
env TARGET_LOCK="${TARGET_LOCK}" "${SCRIPT_DIR}/validate-elf.sh" "${candidate}"
if ! readelf -hW "${fixture_binary}" | grep -Eq \
    "Class:[[:space:]]+${EXPECTED_CLASS}" ||
    ! readelf -hW "${fixture_binary}" | grep -Eq \
    "Machine:[[:space:]]+${EXPECTED_MACHINE}"; then
    echo "error: readelf smoke fixture has the wrong target identity" >&2
    exit 1
fi
docker run --rm \
    --platform "${TARGET_PLATFORM}" \
    --network none \
    --mount "type=bind,src=${candidate},dst=/readelf,readonly" \
    --mount "type=bind,src=${fixture_binary},dst=/fixture,readonly" \
    --mount "type=bind,src=${SCRIPT_DIR}/smoke-test.sh,dst=/smoke-test,readonly" \
    "${BUILDER_IMAGE}" \
    /smoke-test /readelf /fixture "${EXPECTED_VERSION_OUTPUT}"
read -r candidate_sha256 _ < <(sha256sum "${candidate}")

install -m 0755 "${candidate}" "${OUTPUT_FILE}"
env TARGET_LOCK="${TARGET_LOCK}" "${SCRIPT_DIR}/validate-elf.sh" "${OUTPUT_FILE}"
read -r installed_sha256 _ < <(sha256sum "${OUTPUT_FILE}")
if [[ "${installed_sha256}" != "${candidate_sha256}" ]]; then
    echo "error: installed ${TOOL_NAME} does not match the validated candidate" >&2
    exit 1
fi

echo
echo "Built ${OUTPUT_FILE}"
wc -c "${OUTPUT_FILE}"
sha256sum "${OUTPUT_FILE}"

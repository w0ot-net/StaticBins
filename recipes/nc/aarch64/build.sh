#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
readonly OUTPUT_DIR="${REPO_ROOT}/artifacts/aarch64"
readonly OUTPUT_FILE="${OUTPUT_DIR}/nc"
readonly ENVIRONMENT_LOCK="${REPO_ROOT}/builders/aarch64/environment.lock"
readonly SOURCE_LOCK="${SCRIPT_DIR}/source.lock"
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
: "${SOURCE_SIGNATURE:?missing SOURCE_SIGNATURE in source.lock}"
: "${SOURCE_SIGNING_KEY:?missing SOURCE_SIGNING_KEY in source.lock}"
: "${SOURCE_SIGNER_FINGERPRINT:?missing SOURCE_SIGNER_FINGERPRINT in source.lock}"
readonly SOURCE_VERSION SOURCE_ARCHIVE SOURCE_SHA256
readonly SOURCE_SIGNATURE SOURCE_SIGNING_KEY SOURCE_SIGNER_FINGERPRINT

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
signature_status="$(gpgv --status-fd 1 --keyring "${source_keyring}"     "${source_signature}" "${source_archive}" 2>/dev/null)"
if ! grep -Fq "[GNUPG:] VALIDSIG ${SOURCE_SIGNER_FINGERPRINT} "     <<< "${signature_status}"; then
    echo "error: GNU Netcat signature did not match the locked fingerprint" >&2
    exit 1
fi

echo "Checking AArch64 container support..."
if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" /bin/true     >/dev/null 2>&1; then
    echo "Registering AArch64 QEMU emulation with binfmt_misc..."
    docker run --privileged --rm "${BINFMT_IMAGE}" --install arm64
    if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}"         /bin/true >/dev/null; then
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

echo "Building GNU Netcat ${SOURCE_VERSION} for AArch64 with Docker Buildx..."
docker buildx build     --platform "${PLATFORM}"     --build-arg "BUILDER_IMAGE=${BUILDER_IMAGE}"     --build-arg "BUILD_JOBS=${BUILD_JOBS}"     --output "type=local,dest=${temporary_dir}"     "${SCRIPT_DIR}"

candidate="${temporary_dir}/nc"
"${SCRIPT_DIR}/validate-elf.sh" "${candidate}"
docker run --rm     --platform "${PLATFORM}"     --network none     --mount "type=bind,src=${candidate},dst=/nc,readonly"     --mount "type=bind,src=${SCRIPT_DIR}/smoke-test.sh,dst=/smoke-test,readonly"     "${BUILDER_IMAGE}"     /smoke-test /nc "${SOURCE_VERSION}"
read -r candidate_sha256 _ < <(sha256sum "${candidate}")

install -m 0755 "${candidate}" "${OUTPUT_FILE}"
"${SCRIPT_DIR}/validate-elf.sh" "${OUTPUT_FILE}"
read -r installed_sha256 _ < <(sha256sum "${OUTPUT_FILE}")
if [[ "${installed_sha256}" != "${candidate_sha256}" ]]; then
    echo "error: installed nc does not match the validated candidate" >&2
    exit 1
fi

echo
echo "Built ${OUTPUT_FILE}"
wc -c "${OUTPUT_FILE}"
sha256sum "${OUTPUT_FILE}"

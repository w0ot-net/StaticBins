#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
readonly OUTPUT_DIR="${REPO_ROOT}/artifacts/x86"
readonly OUTPUT_FILE="${OUTPUT_DIR}/tcpdump"
readonly ENVIRONMENT_LOCK="${REPO_ROOT}/builders/x86/environment.lock"
readonly SOURCE_LOCK="${SCRIPT_DIR}/source.lock"
readonly PLATFORM="linux/386"
readonly BUILD_JOBS="${BUILD_JOBS:-8}"

# shellcheck source=../../../builders/x86/environment.lock
. "${ENVIRONMENT_LOCK}"
: "${ALPINE_IMAGE:?missing ALPINE_IMAGE in environment.lock}"
: "${BINFMT_IMAGE:?missing BINFMT_IMAGE in environment.lock}"
: "${BUILDER_IMAGE:?missing BUILDER_IMAGE in environment.lock}"
readonly ALPINE_IMAGE BINFMT_IMAGE BUILDER_IMAGE

# shellcheck source=source.lock
. "${SOURCE_LOCK}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
: "${LIBPCAP_VERSION:?missing LIBPCAP_VERSION in source.lock}"
readonly SOURCE_VERSION LIBPCAP_VERSION

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

echo "Checking x86 container support..."
if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" /bin/true >/dev/null 2>&1; then
    echo "Registering x86 QEMU emulation with binfmt_misc..."
    docker run --privileged --rm "${BINFMT_IMAGE}" --install 386
    if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" /bin/true >/dev/null; then
        echo "error: Docker still cannot run x86 containers" >&2
        exit 1
    fi
fi

echo "Checking for the published reusable builder..."
if ! docker pull --platform "${PLATFORM}" "${BUILDER_IMAGE}"; then
    echo "error: could not pull locked builder ${BUILDER_IMAGE}" >&2
    echo "Publish with ./builders/publish.sh x86, then lock its reported digest." >&2
    exit 1
fi

temporary_dir="$(mktemp -d)"
mkdir -p "${OUTPUT_DIR}"

build_args=(
    --build-arg "BUILDER_IMAGE=${BUILDER_IMAGE}"
    --build-arg "BUILD_JOBS=${BUILD_JOBS}"
)

echo "Building tcpdump ${SOURCE_VERSION} with libpcap ${LIBPCAP_VERSION} using Docker Buildx..."
docker buildx build \
    --platform "${PLATFORM}" \
    "${build_args[@]}" \
    --output "type=local,dest=${temporary_dir}" \
    "${SCRIPT_DIR}"

candidate="${temporary_dir}/tcpdump"
validate_elf() {
    local binary="$1"
    if ! file "${binary}" | grep -Eq 'ELF 32-bit LSB executable, Intel (i386|80386)'; then
        echo "error: output is not a 32-bit little-endian x86 executable" >&2
        exit 1
    fi
    if ! readelf -h "${binary}" | grep -Eq 'Class:[[:space:]]+ELF32'; then
        echo "error: output is not ELF32" >&2
        exit 1
    fi
    if ! readelf -h "${binary}" | grep -Eq "Data:[[:space:]]+2's complement, little endian"; then
        echo "error: output is not little-endian" >&2
        exit 1
    fi
    if ! readelf -h "${binary}" | grep -Eq 'Type:[[:space:]]+EXEC'; then
        echo "error: output is not an ELF ET_EXEC executable" >&2
        exit 1
    fi
    if ! readelf -h "${binary}" | grep -Eq 'Machine:[[:space:]]+Intel 80386'; then
        echo "error: output is not an Intel 80386 executable" >&2
        exit 1
    fi
    if readelf -l "${binary}" | grep -q 'Requesting program interpreter'; then
        echo "error: output has a dynamic program interpreter" >&2
        exit 1
    fi
    if readelf -d "${binary}" 2>/dev/null | grep -q '(NEEDED)'; then
        echo "error: output has dynamic library dependencies" >&2
        exit 1
    fi
    if readelf -S "${binary}" | grep -Eq '[.]debug|[.]symtab'; then
        echo "error: output retains debug or full symbol-table sections" >&2
        exit 1
    fi
}

validate_elf "${candidate}"
docker run --rm \
    --platform "${PLATFORM}" \
    --mount "type=bind,src=${candidate},dst=/tcpdump,readonly" \
    --mount "type=bind,src=${SCRIPT_DIR}/smoke-test.sh,dst=/smoke-test,readonly" \
    "${ALPINE_IMAGE}" \
    /smoke-test /tcpdump
read -r candidate_sha256 _ < <(sha256sum "${candidate}")

install -m 0755 "${candidate}" "${OUTPUT_FILE}"
validate_elf "${OUTPUT_FILE}"
read -r installed_sha256 _ < <(sha256sum "${OUTPUT_FILE}")
if [[ "${installed_sha256}" != "${candidate_sha256}" ]]; then
    echo "error: installed tcpdump does not match the validated candidate" >&2
    exit 1
fi

echo
echo "Built ${OUTPUT_FILE}"
wc -c "${OUTPUT_FILE}"
sha256sum "${OUTPUT_FILE}"

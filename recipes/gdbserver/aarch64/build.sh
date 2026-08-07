#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
readonly OUTPUT_DIR="${REPO_ROOT}/artifacts/aarch64"
readonly OUTPUT_FILE="${OUTPUT_DIR}/gdbserver"
readonly ENVIRONMENT_LOCK="${REPO_ROOT}/builders/aarch64/environment.lock"
readonly SOURCE_LOCK="${SCRIPT_DIR}/source.lock"
readonly VM_LOCK="${SCRIPT_DIR}/vm.lock"
readonly PLATFORM="linux/arm64"
readonly BUILD_JOBS="${BUILD_JOBS:-8}"
readonly CACHE_ROOT="${STATIC_BINS_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/static_bins}"

# shellcheck source=../../../builders/aarch64/environment.lock
. "${ENVIRONMENT_LOCK}"
: "${ALPINE_IMAGE:?missing ALPINE_IMAGE in environment.lock}"
: "${BINFMT_IMAGE:?missing BINFMT_IMAGE in environment.lock}"
: "${BUILDER_IMAGE:?missing BUILDER_IMAGE in environment.lock}"
readonly ALPINE_IMAGE BINFMT_IMAGE BUILDER_IMAGE

# shellcheck source=source.lock
. "${SOURCE_LOCK}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
readonly SOURCE_VERSION

# shellcheck source=vm.lock
. "${VM_LOCK}"
: "${VM_KERNEL_FILE:?missing VM_KERNEL_FILE in vm.lock}"
: "${VM_KERNEL_RELEASE:?missing VM_KERNEL_RELEASE in vm.lock}"
: "${VM_KERNEL_URL:?missing VM_KERNEL_URL in vm.lock}"
: "${VM_KERNEL_SHA256:?missing VM_KERNEL_SHA256 in vm.lock}"
: "${VM_KERNEL_AUTHENTICATION:?missing VM_KERNEL_AUTHENTICATION in vm.lock}"
readonly VM_KERNEL_FILE VM_KERNEL_RELEASE VM_KERNEL_URL VM_KERNEL_SHA256
readonly VM_KERNEL_AUTHENTICATION

case "${VM_KERNEL_FILE}" in
    */* | "")
        echo "error: VM_KERNEL_FILE must be a filename" >&2
        exit 1
        ;;
esac
if [[ "${VM_KERNEL_URL}" != https://* ]]; then
    echo "error: VM kernel provenance URL must use HTTPS" >&2
    exit 1
fi
if [[ ! "${VM_KERNEL_SHA256}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: VM kernel SHA-256 must contain 64 lowercase hexadecimal characters" >&2
    exit 1
fi
if [[ "${VM_KERNEL_AUTHENTICATION}" != "checksum-only" ]]; then
    echo "error: unsupported VM kernel authentication mode: ${VM_KERNEL_AUTHENTICATION}" >&2
    exit 1
fi

temporary_dir=""
cleanup() {
    if [[ -n "${temporary_dir}" ]]; then
        rm -rf -- "${temporary_dir}"
    fi
}
trap cleanup EXIT HUP INT TERM

for command_name in cpio curl docker file gzip qemu-system-aarch64 readelf sha256sum timeout; do
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

kernel_cache_dir="${CACHE_ROOT}/vm-kernels"
kernel="${kernel_cache_dir}/${VM_KERNEL_SHA256}-${VM_KERNEL_FILE}"
mkdir -p "${kernel_cache_dir}"
if [[ ! -f "${kernel}" ]]; then
    kernel_download="$(mktemp "${kernel_cache_dir}/.${VM_KERNEL_FILE}.XXXXXX")"
    temporary_dir="${kernel_download}"
    echo "Downloading the pinned AArch64 smoke-test kernel..."
    curl --fail --location --show-error --silent \
        "${VM_KERNEL_URL}" -o "${kernel_download}"
    echo "${VM_KERNEL_SHA256}  ${kernel_download}" | sha256sum -c -
    chmod 0644 "${kernel_download}"
    mv -- "${kernel_download}" "${kernel}"
    temporary_dir=""
fi
if ! echo "${VM_KERNEL_SHA256}  ${kernel}" | sha256sum -c -; then
    echo "error: cached VM kernel failed verification: ${kernel}" >&2
    echo "Remove that exact cache file and rerun the build." >&2
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
if ! docker pull --platform "${PLATFORM}" "${BUILDER_IMAGE}"; then
    echo "error: could not pull locked builder ${BUILDER_IMAGE}" >&2
    echo "Publish with ./builders/publish.sh aarch64, then lock its reported digest." >&2
    exit 1
fi

temporary_dir="$(mktemp -d)"
mkdir -p "${OUTPUT_DIR}"

echo "Building GDBserver ${SOURCE_VERSION} for ARM64 with Docker Buildx..."
docker buildx build \
    --platform "${PLATFORM}" \
    --build-arg "BUILDER_IMAGE=${BUILDER_IMAGE}" \
    --build-arg "BUILD_JOBS=${BUILD_JOBS}" \
    --output "type=local,dest=${temporary_dir}" \
    "${SCRIPT_DIR}"

candidate="${temporary_dir}/gdbserver"
vm_smoke="${temporary_dir}/vm-smoke"
smoke_target="${temporary_dir}/smoke-target"
validate_elf() {
    local binary="$1"
    file "${binary}"
    if ! readelf -h "${binary}" | grep -Eq 'Type:[[:space:]]+EXEC'; then
        echo "error: output is not an ELF ET_EXEC executable" >&2
        exit 1
    fi
    if ! readelf -h "${binary}" | grep -Eq 'Machine:[[:space:]]+AArch64'; then
        echo "error: output is not an AArch64 executable" >&2
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
version_output="$(docker run --rm \
    --platform "${PLATFORM}" \
    --network none \
    --mount "type=bind,src=${candidate},dst=/gdbserver,readonly" \
    "${BUILDER_IMAGE}" \
    /gdbserver --version)"
printf '%s\n' "${version_output}"
if [[ "$(printf '%s\n' "${version_output}" | sed -n '1p')" != \
    "GNU gdbserver (GDB) ${SOURCE_VERSION}" ]]; then
    echo "error: unexpected GDBserver version" >&2
    exit 1
fi
"${SCRIPT_DIR}/smoke-test.sh" \
    "${candidate}" "${vm_smoke}" "${smoke_target}" "${kernel}"
read -r candidate_sha256 _ < <(sha256sum "${candidate}")

install -m 0755 "${candidate}" "${OUTPUT_FILE}"
validate_elf "${OUTPUT_FILE}"
read -r installed_sha256 _ < <(sha256sum "${OUTPUT_FILE}")
if [[ "${installed_sha256}" != "${candidate_sha256}" ]]; then
    echo "error: installed GDBserver does not match the validated candidate" >&2
    exit 1
fi

echo
echo "Built ${OUTPUT_FILE}"
wc -c "${OUTPUT_FILE}"
sha256sum "${OUTPUT_FILE}"

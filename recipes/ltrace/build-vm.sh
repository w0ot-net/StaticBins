#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "usage: $0 ARCHITECTURE" >&2
    exit 2
fi

readonly ARCHITECTURE="$1"
readonly TOOL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${TOOL_DIR}/../.." && pwd)"
readonly SCRIPT_DIR="${TOOL_DIR}/${ARCHITECTURE}"
readonly OUTPUT_DIR="${REPO_ROOT}/artifacts/${ARCHITECTURE}"
readonly OUTPUT_FILE="${OUTPUT_DIR}/ltrace"
readonly ENVIRONMENT_LOCK="${REPO_ROOT}/builders/${ARCHITECTURE}/environment.lock"
readonly SOURCE_LOCK="${SCRIPT_DIR}/source.lock"
readonly VM_LOCK="${SCRIPT_DIR}/vm.lock"
readonly BUILD_JOBS="${BUILD_JOBS:-8}"
readonly CACHE_ROOT="${STATIC_BINS_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/static_bins}"

case "${ARCHITECTURE}" in
    aarch64)
        readonly PLATFORM="linux/arm64"
        readonly DISPLAY_ARCHITECTURE="AArch64"
        readonly EXPECTED_MACHINE="AArch64"
        readonly BINFMT_ARCHITECTURE="arm64"
        readonly QEMU_COMMAND="qemu-system-aarch64"
        readonly MUSL_INTERPRETER="/lib/ld-musl-aarch64.so.1"
        ;;
    armv7)
        readonly PLATFORM="linux/arm/v7"
        readonly DISPLAY_ARCHITECTURE="ARMv7"
        readonly EXPECTED_MACHINE="ARM"
        readonly BINFMT_ARCHITECTURE="arm"
        readonly QEMU_COMMAND="qemu-system-arm"
        readonly MUSL_INTERPRETER="/lib/ld-musl-armhf.so.1"
        ;;
    x86)
        readonly PLATFORM="linux/386"
        readonly DISPLAY_ARCHITECTURE="x86"
        readonly EXPECTED_MACHINE="Intel 80386"
        readonly BINFMT_ARCHITECTURE="386"
        readonly QEMU_COMMAND="qemu-system-i386"
        readonly MUSL_INTERPRETER="/lib/ld-musl-i386.so.1"
        ;;
    *)
        echo "error: unsupported ltrace VM architecture: ${ARCHITECTURE}" >&2
        exit 2
        ;;
esac

# shellcheck source=/dev/null
. "${ENVIRONMENT_LOCK}"
: "${ALPINE_IMAGE:?missing ALPINE_IMAGE in environment.lock}"
: "${BINFMT_IMAGE:?missing BINFMT_IMAGE in environment.lock}"
: "${BUILDER_IMAGE:?missing BUILDER_IMAGE in environment.lock}"
readonly ALPINE_IMAGE BINFMT_IMAGE BUILDER_IMAGE

# shellcheck source=/dev/null
. "${SOURCE_LOCK}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
readonly SOURCE_VERSION

# shellcheck source=/dev/null
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

temporary_path=""
cleanup() {
    if [[ -n "${temporary_path}" ]]; then
        rm -rf -- "${temporary_path}"
    fi
}
trap cleanup EXIT HUP INT TERM

for command_name in \
    cpio curl docker file gzip "${QEMU_COMMAND}" readelf sha256sum timeout; do
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
    temporary_path="${kernel_download}"
    echo "Downloading the pinned ${DISPLAY_ARCHITECTURE} smoke-test kernel..."
    curl --fail --location --show-error --silent \
        "${VM_KERNEL_URL}" -o "${kernel_download}"
    echo "${VM_KERNEL_SHA256}  ${kernel_download}" | sha256sum -c -
    chmod 0644 "${kernel_download}"
    mv -- "${kernel_download}" "${kernel}"
    temporary_path=""
fi
if ! echo "${VM_KERNEL_SHA256}  ${kernel}" | sha256sum -c -; then
    echo "error: cached VM kernel failed verification: ${kernel}" >&2
    echo "Remove that exact cache file and rerun the build." >&2
    exit 1
fi

echo "Checking ${DISPLAY_ARCHITECTURE} container support..."
if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" /bin/true \
    >/dev/null 2>&1; then
    echo "Registering ${DISPLAY_ARCHITECTURE} QEMU emulation with binfmt_misc..."
    docker run --privileged --rm "${BINFMT_IMAGE}" \
        --install "${BINFMT_ARCHITECTURE}"
    if ! docker run --rm --platform "${PLATFORM}" "${ALPINE_IMAGE}" \
        /bin/true >/dev/null; then
        echo "error: Docker still cannot run ${DISPLAY_ARCHITECTURE} containers" >&2
        exit 1
    fi
fi

echo "Checking for the published reusable builder..."
if ! docker pull --platform "${PLATFORM}" "${BUILDER_IMAGE}"; then
    echo "error: could not pull locked builder ${BUILDER_IMAGE}" >&2
    echo "Publish with ./builders/publish.sh ${ARCHITECTURE}, then lock its reported digest." >&2
    exit 1
fi

temporary_path="$(mktemp -d)"
mkdir -p "${OUTPUT_DIR}"

echo "Building ltrace ${SOURCE_VERSION} for ${DISPLAY_ARCHITECTURE} with Docker Buildx..."
docker buildx build \
    --platform "${PLATFORM}" \
    --build-arg "BUILDER_IMAGE=${BUILDER_IMAGE}" \
    --build-arg "BUILD_JOBS=${BUILD_JOBS}" \
    --file "${SCRIPT_DIR}/Dockerfile" \
    --output "type=local,dest=${temporary_path}" \
    "${TOOL_DIR}"

candidate="${temporary_path}/ltrace"
vm_smoke="${temporary_path}/vm-smoke"
smoke_target="${temporary_path}/smoke-target"
musl_loader="${temporary_path}/ld-musl.so.1"
validate_machine() {
    local binary="$1"
    if ! readelf -hW "${binary}" | grep -Eq \
        "Machine:[[:space:]]+${EXPECTED_MACHINE}"; then
        echo "error: output has the wrong ELF machine for ${ARCHITECTURE}" >&2
        exit 1
    fi
    case "${ARCHITECTURE}" in
        armv7)
            if ! readelf -hW "${binary}" | grep -Eq \
                'Class:[[:space:]]+ELF32' ||
                ! readelf -hW "${binary}" | grep -Eq \
                'Data:[[:space:]]+2.s complement, little endian' ||
                ! readelf -hW "${binary}" | grep -Eq \
                'Flags:.*hard-float ABI'; then
                echo "error: output is not ARMv7 ELF32 little-endian hard-float" >&2
                exit 1
            fi
            ;;
        x86)
            if ! readelf -hW "${binary}" | grep -Eq \
                'Class:[[:space:]]+ELF32' ||
                ! readelf -hW "${binary}" | grep -Eq \
                'Data:[[:space:]]+2.s complement, little endian'; then
                echo "error: output is not little-endian ELF32 x86" >&2
                exit 1
            fi
            ;;
    esac
}
validate_ltrace() {
    local binary="$1"
    file "${binary}"
    if ! file "${binary}" | grep -q 'static-pie linked'; then
        echo "error: output is not reported as static PIE" >&2
        exit 1
    fi
    validate_machine "${binary}"
    if ! readelf -hW "${binary}" | grep -Eq \
        'Type:[[:space:]]+DYN .*Position-Independent Executable'; then
        echo "error: output is not an ELF static PIE" >&2
        exit 1
    fi
    if ! readelf -hW "${binary}" | grep -Eq \
        'Entry point address:[[:space:]]+0x[1-9a-fA-F][0-9a-fA-F]*'; then
        echo "error: output has no executable entry point" >&2
        exit 1
    fi
    if readelf -lW "${binary}" | grep -q 'Requesting program interpreter'; then
        echo "error: output has a dynamic program interpreter" >&2
        exit 1
    fi
    if readelf -dW "${binary}" 2>/dev/null | grep -q '(NEEDED)'; then
        echo "error: output has dynamic library dependencies" >&2
        exit 1
    fi
    if ! readelf -dW "${binary}" | grep -Eq '\(FLAGS_1\).*PIE'; then
        echo "error: output is not marked PIE" >&2
        exit 1
    fi
    if readelf -dW "${binary}" | grep -q '(TEXTREL)'; then
        echo "error: output contains text relocations" >&2
        exit 1
    fi
    if readelf -SW "${binary}" | grep -Eq '[.]debug|[.]symtab'; then
        echo "error: output retains debug or full symbol-table sections" >&2
        exit 1
    fi
}

validate_ltrace "${candidate}"
validate_machine "${vm_smoke}"
validate_machine "${smoke_target}"
validate_machine "${musl_loader}"
if ! readelf -lW "${smoke_target}" | grep -Fq \
    "Requesting program interpreter: ${MUSL_INTERPRETER}"; then
    echo "error: smoke target does not use the expected musl interpreter" >&2
    exit 1
fi
version_output="$(docker run --rm \
    --platform "${PLATFORM}" \
    --network none \
    --mount "type=bind,src=${candidate},dst=/ltrace,readonly" \
    "${BUILDER_IMAGE}" \
    /ltrace --version 2>&1)"
printf '%s\n' "${version_output}"
if [[ "$(printf '%s\n' "${version_output}" | sed -n '1p')" != \
    "ltrace ${SOURCE_VERSION}" ]]; then
    echo "error: unexpected ltrace version" >&2
    exit 1
fi
"${TOOL_DIR}/vm-smoke-test.sh" \
    "${ARCHITECTURE}" "${candidate}" "${vm_smoke}" "${smoke_target}" \
    "${musl_loader}" "${kernel}"
read -r candidate_sha256 _ < <(sha256sum "${candidate}")

install -m 0755 "${candidate}" "${OUTPUT_FILE}"
validate_ltrace "${OUTPUT_FILE}"
read -r installed_sha256 _ < <(sha256sum "${OUTPUT_FILE}")
if [[ "${installed_sha256}" != "${candidate_sha256}" ]]; then
    echo "error: installed ltrace does not match the validated candidate" >&2
    exit 1
fi

echo
echo "Built ${OUTPUT_FILE}"
wc -c "${OUTPUT_FILE}"
sha256sum "${OUTPUT_FILE}"

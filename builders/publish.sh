#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly BUILDER_REPOSITORY="ghcr.io/w0ot-net/static_bins-builder"

usage() {
    echo "usage: $0 <aarch64|armv7|x86_64>" >&2
}

if (( $# != 1 )); then
    usage
    exit 2
fi

readonly ARCHITECTURE=$1
case "${ARCHITECTURE}" in
    aarch64)
        readonly BUILDER_DIRECTORY="${SCRIPT_DIR}/aarch64"
        readonly PLATFORM="linux/arm64"
        readonly FLOATING_TAG="aarch64-latest"
        readonly TAG_PREFIX="aarch64-"
        ;;
    armv7)
        readonly BUILDER_DIRECTORY="${SCRIPT_DIR}/armv7"
        readonly PLATFORM="linux/arm/v7"
        readonly FLOATING_TAG="armv7-latest"
        readonly TAG_PREFIX="armv7-"
        ;;
    x86_64)
        readonly BUILDER_DIRECTORY="${SCRIPT_DIR}/x86_64"
        readonly PLATFORM="linux/amd64"
        readonly FLOATING_TAG="x64-latest"
        readonly TAG_PREFIX="x64-"
        ;;
    *)
        echo "error: unsupported architecture: ${ARCHITECTURE}" >&2
        usage
        exit 2
        ;;
esac

readonly ENVIRONMENT_LOCK="${BUILDER_DIRECTORY}/environment.lock"

# shellcheck source=/dev/null
. "${ENVIRONMENT_LOCK}"

: "${ALPINE_IMAGE:?missing ALPINE_IMAGE in environment.lock}"
: "${BINFMT_IMAGE:?missing BINFMT_IMAGE in environment.lock}"
: "${BUILDER_TAG:?missing BUILDER_TAG in environment.lock}"

readonly ALPINE_IMAGE BINFMT_IMAGE BUILDER_TAG

case "${ALPINE_IMAGE}" in
    *@sha256:*) ;;
    *)
        echo "error: ALPINE_IMAGE must be pinned by digest" >&2
        exit 1
        ;;
esac

case "${BINFMT_IMAGE}" in
    *@sha256:*) ;;
    *)
        echo "error: BINFMT_IMAGE must be pinned by digest" >&2
        exit 1
        ;;
esac

case "${BUILDER_TAG}" in
    "${TAG_PREFIX}"*) ;;
    *)
        echo "error: BUILDER_TAG must begin with ${TAG_PREFIX}" >&2
        exit 1
        ;;
esac

for command_name in docker mktemp python3; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: required command not found: ${command_name}" >&2
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

temporary_dir="$(mktemp -d)"
cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

readonly VERSIONED_IMAGE="${BUILDER_REPOSITORY}:${BUILDER_TAG}"
readonly FLOATING_IMAGE="${BUILDER_REPOSITORY}:${FLOATING_TAG}"
readonly MANIFEST_ERROR="${temporary_dir}/manifest-error.txt"

if docker manifest inspect "${VERSIONED_IMAGE}" \
    >"${temporary_dir}/existing-manifest.json" 2>"${MANIFEST_ERROR}"; then
    echo "error: versioned builder already exists: ${VERSIONED_IMAGE}" >&2
    exit 1
fi

if ! python3 - "${MANIFEST_ERROR}" <<'PY'
import pathlib
import sys

message = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").lower()
accepted = ("manifest unknown", "not found", "no such manifest")
if not any(marker in message for marker in accepted):
    raise SystemExit(1)
PY
then
    echo "error: could not establish that ${VERSIONED_IMAGE} is unused" >&2
    sed -n '1,20p' "${MANIFEST_ERROR}" >&2
    exit 1
fi

echo "Validating builder candidate for ${ARCHITECTURE}..."
"${BUILDER_DIRECTORY}/build.sh"

readonly METADATA_FILE="${temporary_dir}/metadata.json"
echo "Publishing ${VERSIONED_IMAGE} and ${FLOATING_IMAGE}..."
docker buildx build \
    --platform "${PLATFORM}" \
    --build-arg "ALPINE_IMAGE=${ALPINE_IMAGE}" \
    --file "${BUILDER_DIRECTORY}/Dockerfile" \
    --push \
    --tag "${VERSIONED_IMAGE}" \
    --tag "${FLOATING_IMAGE}" \
    --sbom=true \
    --provenance=mode=max \
    --metadata-file "${METADATA_FILE}" \
    "${BUILDER_DIRECTORY}"

published_digest="$(python3 - "${METADATA_FILE}" <<'PY'
import json
import pathlib
import re
import sys

metadata = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
digest = metadata.get("containerimage.digest", "")
if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
    raise SystemExit("error: Buildx metadata did not contain a valid container-image digest")
print(digest)
PY
)"
readonly published_digest

readonly INSPECTION_FILE="${temporary_dir}/published-image.json"
docker buildx imagetools inspect "${VERSIONED_IMAGE}" \
    --format '{{json .}}' >"${INSPECTION_FILE}"

python3 - "${INSPECTION_FILE}" "${published_digest}" "${PLATFORM}" <<'PY'
import json
import pathlib
import sys

inspection = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
expected_digest = sys.argv[2]
expected_platform = sys.argv[3].split("/")
manifest = inspection.get("manifest", {})

if manifest.get("digest") != expected_digest:
    raise SystemExit("error: published reference digest does not match Buildx metadata")

matches = []
for entry in manifest.get("manifests", []):
    platform = entry.get("platform", {})
    observed = [platform.get("os"), platform.get("architecture")]
    if len(expected_platform) == 3:
        observed.append(platform.get("variant"))
    if observed == expected_platform:
        matches.append(entry)

if len(matches) != 1:
    raise SystemExit(
        f"error: published reference contains {len(matches)} manifests for {sys.argv[3]}"
    )
PY

echo "Published immutable builder: ${VERSIONED_IMAGE}@${published_digest}"
echo "Adopt it in ${ENVIRONMENT_LOCK#${REPO_ROOT}/}:"
echo "BUILDER_IMAGE=${BUILDER_REPOSITORY}@${published_digest}"

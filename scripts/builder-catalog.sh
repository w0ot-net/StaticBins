#!/usr/bin/env bash

# Strict shared loader for builders/catalog.tsv. Callers provide the catalog
# path and repository root, then consume BUILDER_ARCHITECTURES,
# BUILDER_PLATFORMS, and BUILDER_TAG_PREFIXES.
load_builder_catalog() {
    if (( $# != 2 )); then
        echo "error: load_builder_catalog requires CATALOG and REPOSITORY_ROOT" >&2
        return 1
    fi

    local catalog_path="$1"
    local repository_root="$2"
    local expected_header=$'architecture\tplatform\ttag_prefix'
    local row_pattern=$'^([^\t]+)\t([^\t]+)\t([^\t]+)$'
    local lock_pattern='^([A-Z][A-Z0-9_]*)=([^[:space:]#]+)$'
    local digest_image_pattern='^[^@[:space:]]+@sha256:[0-9a-f]{64}$'
    local LC_ALL=C

    if [[ ! -f "${catalog_path}" || -L "${catalog_path}" || ! -r "${catalog_path}" ]]; then
        echo "error: missing regular builder catalog: ${catalog_path}" >&2
        return 1
    fi

    local catalog_header
    if ! IFS= read -r catalog_header < "${catalog_path}"; then
        echo "error: builder catalog is empty: ${catalog_path}" >&2
        return 1
    fi
    if [[ "${catalog_header}" != "${expected_header}" ]]; then
        echo "error: builder catalog header does not match the required schema" >&2
        return 1
    fi

    declare -g -a BUILDER_ARCHITECTURES=()
    declare -g -A BUILDER_PLATFORMS=()
    declare -g -A BUILDER_TAG_PREFIXES=()
    local -A seen_tag_prefixes=()
    local previous_architecture=""
    local line_number=1
    local catalog_line architecture platform tag_prefix

    while IFS= read -r catalog_line || [[ -n "${catalog_line}" ]]; do
        line_number=$((line_number + 1))
        if [[ -z "${catalog_line}" ]]; then
            echo "error: builder catalog line ${line_number}: blank row" >&2
            return 1
        fi
        if [[ ! "${catalog_line}" =~ ${row_pattern} ]]; then
            echo "error: builder catalog line ${line_number}: wrong number of tab-delimited fields" >&2
            return 1
        fi

        architecture="${BASH_REMATCH[1]}"
        platform="${BASH_REMATCH[2]}"
        tag_prefix="${BASH_REMATCH[3]}"

        if [[ ! "${architecture}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
            echo "error: builder catalog line ${line_number}: invalid architecture: ${architecture}" >&2
            return 1
        fi
        if [[ ! "${platform}" =~ ^linux/[a-z0-9][a-z0-9_-]*(/[a-z0-9][a-z0-9._-]*)?$ ]]; then
            echo "error: builder catalog line ${line_number}: invalid platform: ${platform}" >&2
            return 1
        fi
        if [[ ! "${tag_prefix}" =~ ^[a-z0-9][a-z0-9._-]*-$ ]]; then
            echo "error: builder catalog line ${line_number}: invalid tag prefix: ${tag_prefix}" >&2
            return 1
        fi
        if [[ -n "${BUILDER_PLATFORMS[${architecture}]+present}" ]]; then
            echo "error: builder catalog line ${line_number}: duplicate architecture: ${architecture}" >&2
            return 1
        fi
        if [[ -n "${previous_architecture}" && ! "${architecture}" > "${previous_architecture}" ]]; then
            echo "error: builder catalog line ${line_number}: architectures are not sorted" >&2
            return 1
        fi
        if [[ -n "${seen_tag_prefixes[${tag_prefix}]+present}" ]]; then
            echo "error: builder catalog line ${line_number}: duplicate tag prefix: ${tag_prefix}" >&2
            return 1
        fi

        local builder_directory="${repository_root}/builders/${architecture}"
        local owned_path
        for owned_path in Dockerfile packages.lock environment.lock; do
            if [[ ! -f "${builder_directory}/${owned_path}" || -L "${builder_directory}/${owned_path}" ]]; then
                echo "error: builder catalog line ${line_number}: missing regular builder file: builders/${architecture}/${owned_path}" >&2
                return 1
            fi
        done
        if [[ ! -f "${builder_directory}/build.sh" || -L "${builder_directory}/build.sh" || ! -x "${builder_directory}/build.sh" ]]; then
            echo "error: builder catalog line ${line_number}: missing executable builder command: builders/${architecture}/build.sh" >&2
            return 1
        fi

        local -A lock_values=()
        local lock_line lock_key lock_value
        local lock_line_number=0
        while IFS= read -r lock_line || [[ -n "${lock_line}" ]]; do
            lock_line_number=$((lock_line_number + 1))
            [[ -z "${lock_line}" || "${lock_line}" == \#* ]] && continue
            if [[ ! "${lock_line}" =~ ${lock_pattern} ]]; then
                echo "error: builders/${architecture}/environment.lock line ${lock_line_number}: unsafe assignment" >&2
                return 1
            fi
            lock_key="${BASH_REMATCH[1]}"
            lock_value="${BASH_REMATCH[2]}"
            if [[ -n "${lock_values[${lock_key}]+present}" ]]; then
                echo "error: builders/${architecture}/environment.lock line ${lock_line_number}: duplicate ${lock_key}" >&2
                return 1
            fi
            lock_values["${lock_key}"]="${lock_value}"
        done < "${builder_directory}/environment.lock"

        local required_key
        for required_key in ALPINE_IMAGE BINFMT_IMAGE BUILDER_TAG BUILDER_IMAGE; do
            if [[ -z "${lock_values[${required_key}]+present}" ]]; then
                echo "error: builders/${architecture}/environment.lock is missing ${required_key}" >&2
                return 1
            fi
        done
        for required_key in ALPINE_IMAGE BINFMT_IMAGE BUILDER_IMAGE; do
            if [[ ! "${lock_values[${required_key}]}" =~ ${digest_image_pattern} ]]; then
                echo "error: builders/${architecture}/environment.lock must pin ${required_key} by SHA-256 digest" >&2
                return 1
            fi
        done
        if [[ ! "${lock_values[BUILDER_TAG]}" =~ ^[a-z0-9][a-z0-9._-]*$ || "${lock_values[BUILDER_TAG]}" != "${tag_prefix}"* ]]; then
            echo "error: builders/${architecture}/environment.lock BUILDER_TAG must begin with ${tag_prefix}" >&2
            return 1
        fi

        BUILDER_ARCHITECTURES+=("${architecture}")
        BUILDER_PLATFORMS["${architecture}"]="${platform}"
        BUILDER_TAG_PREFIXES["${architecture}"]="${tag_prefix}"
        seen_tag_prefixes["${tag_prefix}"]=1
        previous_architecture="${architecture}"
    done < <(tail -n +2 "${catalog_path}")

    if (( ${#BUILDER_ARCHITECTURES[@]} == 0 )); then
        echo "error: builder catalog has no architectures" >&2
        return 1
    fi
}

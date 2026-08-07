#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CATALOG="${SCRIPT_DIR}/recipes/catalog.tsv"
readonly HEADER=$'name\tarchitecture\tenabled'

usage() {
    echo "usage: ./build.sh list | ./build.sh <recipe> [architecture]" >&2
}

if [[ $# -lt 1 || $# -gt 2 || ( "$1" == "list" && $# -ne 1 ) ]]; then
    usage
    exit 2
fi

if [[ ! -r "${CATALOG}" ]]; then
    echo "error: missing recipe catalog: ${CATALOG}" >&2
    exit 1
fi

IFS= read -r catalog_header < "${CATALOG}"
if [[ "${catalog_header}" != "${HEADER}" ]]; then
    echo "error: recipe catalog header does not match the required schema" >&2
    exit 1
fi

readonly requested_recipe="$1"
if [[ "${requested_recipe}" != "list" && ! "${requested_recipe}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "error: unsafe recipe name: ${requested_recipe}" >&2
    exit 2
fi

requested_architecture="${2:-}"
if [[ -n "${requested_architecture}" ]]; then
    case "${requested_architecture}" in
        aarch64 | armv7 | x86_64) ;;
        *)
            echo "error: unsupported architecture: ${requested_architecture}" >&2
            exit 2
            ;;
    esac
fi

match_count=0
matched_enabled=""
matched_script=""
declare -a matched_architectures=()
declare -A seen_pairs=()

while IFS= read -r catalog_line || [[ -n "${catalog_line}" ]]; do
    [[ -n "${catalog_line}" ]] || {
        echo "error: blank recipe catalog row" >&2
        exit 1
    }
    IFS=$'\t' read -r -a columns <<< "${catalog_line}"
    if [[ ${#columns[@]} -ne 3 ]]; then
        echo "error: malformed recipe catalog row" >&2
        exit 1
    fi

    name="${columns[0]}"
    architecture="${columns[1]}"
    enabled="${columns[2]}"

    if [[ ! "${name}" =~ ^[a-z0-9][a-z0-9_-]*$ || "${name}" == "list" ]]; then
        echo "error: invalid recipe name in catalog: ${name}" >&2
        exit 1
    fi
    case "${architecture}" in
        aarch64 | armv7 | x86_64) ;;
        *)
            echo "error: unsupported architecture for ${name}: ${architecture}" >&2
            exit 1
            ;;
    esac
    pair="${name}/${architecture}"
    if [[ -n "${seen_pairs[${pair}]:-}" ]]; then
        echo "error: duplicate recipe pair in catalog: ${pair}" >&2
        exit 1
    fi
    seen_pairs["${pair}"]=1
    if [[ "${enabled}" != "true" && "${enabled}" != "false" ]]; then
        echo "error: invalid enabled value for ${name}" >&2
        exit 1
    fi

    build_script="recipes/${name}/${architecture}/build.sh"
    absolute_script="${SCRIPT_DIR}/${build_script}"
    if [[ "${enabled}" == "true" && (! -f "${absolute_script}" || ! -x "${absolute_script}") ]]; then
        echo "error: recipe build script is missing or not executable: ${absolute_script}" >&2
        exit 1
    fi

    if [[ "${requested_recipe}" == "list" ]]; then
        if [[ "${enabled}" == "true" ]]; then
            printf '%s\t%s\n' "${name}" "${architecture}"
        fi
        continue
    fi

    if [[ "${name}" == "${requested_recipe}" && ( -z "${requested_architecture}" || "${architecture}" == "${requested_architecture}" ) ]]; then
        match_count=$((match_count + 1))
        matched_enabled="${enabled}"
        matched_script="${absolute_script}"
        matched_architectures+=("${architecture}")
    fi
done < <(tail -n +2 "${CATALOG}")

if [[ "${requested_recipe}" == "list" ]]; then
    exit 0
fi
if [[ ${match_count} -eq 0 ]]; then
    if [[ -n "${requested_architecture}" ]]; then
        echo "error: unknown recipe: ${requested_recipe}/${requested_architecture}" >&2
    else
        echo "error: unknown recipe: ${requested_recipe}" >&2
    fi
    exit 2
fi
if [[ ${match_count} -ne 1 ]]; then
    echo "error: recipe '${requested_recipe}' is available for multiple architectures; choose one:" >&2
    for architecture in "${matched_architectures[@]}"; do
        echo "  ./build.sh ${requested_recipe} ${architecture}" >&2
    done
    exit 2
fi
if [[ "${matched_enabled}" != "true" ]]; then
    if [[ -n "${requested_architecture}" ]]; then
        echo "error: recipe is disabled: ${requested_recipe}/${requested_architecture}" >&2
    else
        echo "error: recipe is disabled: ${requested_recipe}" >&2
    fi
    exit 2
fi

cd -- "${SCRIPT_DIR}"
exec "${matched_script}"

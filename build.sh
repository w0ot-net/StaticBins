#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CATALOG="${SCRIPT_DIR}/recipes/catalog.tsv"
readonly HEADER=$'name\tarchitecture\tenabled'

usage() {
    echo "usage: ./build.sh list | ./build.sh <recipe>" >&2
}

if [[ $# -ne 1 ]]; then
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

match_count=0
matched_enabled=""
matched_script=""
declare -A seen_names=()

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
    if [[ -n "${seen_names[${name}]:-}" ]]; then
        echo "error: duplicate recipe name in catalog: ${name}" >&2
        exit 1
    fi
    seen_names["${name}"]=1
    case "${architecture}" in
        aarch64 | x86_64) ;;
        *)
            echo "error: unsupported architecture for ${name}: ${architecture}" >&2
            exit 1
            ;;
    esac
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
            printf '%s\n' "${name}"
        fi
        continue
    fi

    if [[ "${name}" == "${requested_recipe}" ]]; then
        match_count=$((match_count + 1))
        matched_enabled="${enabled}"
        matched_script="${absolute_script}"
    fi
done < <(tail -n +2 "${CATALOG}")

if [[ "${requested_recipe}" == "list" ]]; then
    exit 0
fi
if [[ ${match_count} -eq 0 ]]; then
    echo "error: unknown recipe: ${requested_recipe}" >&2
    exit 2
fi
if [[ ${match_count} -ne 1 ]]; then
    echo "error: duplicate recipe: ${requested_recipe}" >&2
    exit 1
fi
if [[ "${matched_enabled}" != "true" ]]; then
    echo "error: recipe is disabled: ${requested_recipe}" >&2
    exit 2
fi

cd -- "${SCRIPT_DIR}"
exec "${matched_script}"

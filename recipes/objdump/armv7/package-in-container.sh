#!/bin/sh

set -eu

recipe_root=/usr/local/share/static_bins/binutils
source_lock="${recipe_root}/source.lock"
target_lock="${recipe_root}/target.lock"
license_dir=/usr/local/share/licenses/binutils
inventory="${license_dir}/archive-inventory.tsv"
build_dir=/build/binutils-build

# shellcheck source=source.lock
. "${source_lock}"
# shellcheck source=target.lock
. "${target_lock}"

: "${SOURCE_VERSION:?missing SOURCE_VERSION}"
: "${EXPECTED_VERSION_OUTPUT:?missing EXPECTED_VERSION_OUTPUT}"
: "${SOURCE_LICENSE:?missing SOURCE_LICENSE}"
: "${TARGET_LOCK:?TARGET_LOCK must identify the installed target lock}"

for command_name in apk awk grep readelf readlink sed sort strip; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done
if [ ! -r "${inventory}" ]; then
    echo "error: missing Binutils linked-input inventory" >&2
    exit 1
fi

tab="$(printf '\t')"
inventory_errors=0
for tool_name in objdump readelf nm; do
    map_file="/out/${tool_name}-link.map"
    raw_file="/out/${tool_name}-linked-archives.raw"
    matched_file="/out/${tool_name}-matched-inventory.txt"
    awk '
        $1 == "LOAD" && $2 ~ /[.]a$/ { print $2 }
        {
            line = $0
            while (match(line, /[^[:space:]()]+[.]a[(]/)) {
                archive = substr(line, RSTART, RLENGTH - 1)
                print archive
                line = substr(line, RSTART + RLENGTH)
            }
        }
    ' "${map_file}" | sort -u > "${raw_file}"
    : > "${matched_file}"

    while IFS= read -r linked_archive; do
        case "${linked_archive}" in
            /*) archive_path="${linked_archive}" ;;
            *) archive_path="${build_dir}/binutils/${linked_archive}" ;;
        esac
        archive_path="$(readlink -f "${archive_path}")"
        if ! awk -F '\t' -v tool="${tool_name}" -v path="${archive_path}" \
            '$1 == tool && $2 == path { found = 1 } END { if (!found) exit 1 }' \
            "${inventory}"; then
            echo "error: ${tool_name}: linked archive is not inventoried: ${archive_path}" >&2
            inventory_errors=$((inventory_errors + 1))
            continue
        fi
        printf '%s\n' "${archive_path}" >> "${matched_file}"
    done < "${raw_file}"

    while IFS="${tab}" read -r row_tool archive_path origin package version \
        license license_file source_evidence; do
        case "${row_tool}" in "" | \#*) continue ;; esac
        [ "${row_tool}" = "${tool_name}" ] || continue
        if ! grep -Fxq "${archive_path}" "${matched_file}"; then
            echo "error: ${tool_name}: inventoried archive was not linked: ${archive_path}" >&2
            inventory_errors=$((inventory_errors + 1))
            continue
        fi
        if [ -z "${package}" ] || [ -z "${version}" ] || [ -z "${license}" ] ||
            [ ! -r "${license_dir}/${license_file}" ] || [ -z "${source_evidence}" ]; then
            echo "error: ${tool_name}: incomplete evidence for ${archive_path}" >&2
            inventory_errors=$((inventory_errors + 1))
            continue
        fi
        case "${origin}" in
            source)
                case "${archive_path}" in
                    "${build_dir}"/*) ;;
                    *)
                        echo "error: source archive is outside the verified build tree: ${archive_path}" >&2
                        inventory_errors=$((inventory_errors + 1))
                        ;;
                esac
                ;;
            builder)
                installed_owner="$(apk info -W "${archive_path}" | sed 's/.* is owned by //')"
                if [ "${installed_owner}" != "${package}-${version}" ]; then
                    echo "error: ${archive_path}: expected ${package}-${version}, found ${installed_owner}" >&2
                    inventory_errors=$((inventory_errors + 1))
                fi
                installed_license="$(sed -n "/^P:${package}$/,/^$/s/^L://p" /lib/apk/db/installed)"
                if [ "${installed_license}" != "${license}" ]; then
                    echo "error: ${package}: expected license '${license}', found '${installed_license}'" >&2
                    inventory_errors=$((inventory_errors + 1))
                fi
                ;;
            *)
                echo "error: ${tool_name}: invalid origin for ${archive_path}: ${origin}" >&2
                inventory_errors=$((inventory_errors + 1))
                ;;
        esac
    done < "${inventory}"
done

if [ "${inventory_errors}" -ne 0 ]; then
    for tool_name in objdump readelf nm; do
        echo "${tool_name} linked archives:" >&2
        cat "/out/${tool_name}-linked-archives.raw" >&2
    done
    exit 1
fi

install -m 0755 "${build_dir}/binutils/objdump" /out/objdump
install -m 0755 "${build_dir}/binutils/readelf" /out/readelf
install -m 0755 "${build_dir}/binutils/nm-new" /out/nm
strip /out/objdump /out/readelf /out/nm

for tool_name in objdump readelf nm; do
    TARGET_LOCK="${target_lock}" /usr/local/bin/validate-binutils-elf \
        "/out/${tool_name}"
    version_line="$("/out/${tool_name}" --version | sed -n '1p')"
    if [ "${version_line}" != "GNU ${tool_name} (GNU Binutils) ${EXPECTED_VERSION_OUTPUT}" ]; then
        echo "error: unexpected ${tool_name} version: ${version_line}" >&2
        exit 1
    fi
done

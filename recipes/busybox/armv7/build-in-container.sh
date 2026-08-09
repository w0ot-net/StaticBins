#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

source_lock="/usr/local/share/static_bins/busybox/source.lock"
source_input_dir="/usr/local/share/static_bins/busybox/sources"
committed_config="/usr/local/share/static_bins/busybox/busybox.config"
expected_applets="/usr/local/share/static_bins/busybox/expected-applets.txt"
license_dir="/usr/local/share/licenses/busybox"
archive_inventory="${license_dir}/archive-inventory.tsv"
validator="/usr/local/bin/validate-busybox-elf"
fixed_timestamp="1970-01-01 00:00:00 +0000"

# shellcheck source=source.lock
. "${source_lock}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE in source.lock}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256 in source.lock}"
: "${SOURCE_LICENSE:?missing SOURCE_LICENSE in source.lock}"

for command_name in awk cmp cp file make readelf readlink sha256sum sort strip tar yes; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done
for required_input in "${committed_config}" "${expected_applets}" "${archive_inventory}"; do
    if [ ! -r "${required_input}" ]; then
        echo "error: missing BusyBox recipe input: ${required_input}" >&2
        exit 1
    fi
done

mkdir -p /build /out
source_archive="/build/${SOURCE_ARCHIVE}"
cp "${source_input_dir}/${SOURCE_ARCHIVE}" "${source_archive}"
printf '%s  %s\n' "${SOURCE_SHA256}" "${source_archive}" | sha256sum -c -
tar -xf "${source_archive}" -C /build
source_dir="/build/busybox-${SOURCE_VERSION}"
cd "${source_dir}"

cp "${committed_config}" .config
cp "${committed_config}" /out/busybox.config.expected
if ! (yes "" | KBUILD_BUILD_TIMESTAMP="${fixed_timestamp}" SOURCE_DATE_EPOCH=0 \
    make oldconfig) > /out/busybox-oldconfig.log 2>&1; then
    cat /out/busybox-oldconfig.log >&2
    exit 1
fi
if ! cmp /out/busybox.config.expected .config; then
    echo "error: BusyBox oldconfig changed the committed configuration" >&2
    exit 1
fi

if ! KBUILD_BUILD_TIMESTAMP="${fixed_timestamp}" SOURCE_DATE_EPOCH=0 \
    make -j"${BUILD_JOBS}" V=1 \
        EXTRA_LDFLAGS="-Wl,-Map,/out/busybox-link.map" \
        > /out/busybox-build.log 2>&1; then
    tail -n 200 /out/busybox-build.log >&2
    exit 1
fi
tail -n 12 /out/busybox-build.log

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
' /out/busybox-link.map | sort -u > /out/linked-archives.raw

: > /out/linked-archives.txt
: > /out/matched-inventory.txt
inventory_errors=0
while IFS= read -r linked_archive; do
    case "${linked_archive}" in
        /*) archive_path="${linked_archive}" ;;
        *) archive_path="${source_dir}/${linked_archive}" ;;
    esac
    archive_path="$(readlink -f "${archive_path}")"
    inventory_row="$(awk -F '\t' -v path="${archive_path}" \
        '$1 == path { print; found = 1 } END { if (!found) exit 1 }' \
        "${archive_inventory}")" || {
            echo "error: linked archive is not inventoried: ${archive_path}" >&2
            inventory_errors=$((inventory_errors + 1))
            continue
        }
    printf '%s\n' "${inventory_row}" >> /out/linked-archives.txt
    printf '%s\n' "${archive_path}" >> /out/matched-inventory.txt
done < /out/linked-archives.raw

tab="$(printf '\t')"
while IFS="${tab}" read -r archive_path origin package version license license_file source_evidence; do
    case "${archive_path}" in "" | \#*) continue ;; esac
    if ! grep -Fxq "${archive_path}" /out/matched-inventory.txt; then
        echo "error: inventoried archive was not present in final link: ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    if [ -z "${package}" ] || [ -z "${version}" ] || [ -z "${license}" ] ||
        [ ! -r "${license_dir}/${license_file}" ] || [ -z "${source_evidence}" ]; then
        echo "error: incomplete license/source evidence for ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    case "${origin}" in
        source)
            case "${archive_path}" in
                "${source_dir}"/*) ;;
                *)
                    echo "error: source archive is outside BusyBox tree: ${archive_path}" >&2
                    inventory_errors=$((inventory_errors + 1))
                    continue
                    ;;
            esac
            if [ "${package}" != BusyBox ] || [ "${version}" != "${SOURCE_VERSION}" ]; then
                echo "error: wrong BusyBox source inventory identity: ${archive_path}" >&2
                inventory_errors=$((inventory_errors + 1))
            fi
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
            echo "error: unknown archive origin for ${archive_path}: ${origin}" >&2
            inventory_errors=$((inventory_errors + 1))
            ;;
    esac
done < "${archive_inventory}"

if [ "${inventory_errors}" -ne 0 ]; then
    echo "Linked archives observed in the final map:" >&2
    cat /out/linked-archives.raw >&2
    exit 1
fi

install -m 0755 busybox /out/busybox
strip /out/busybox
"${validator}" /out/busybox

version_line="$(/out/busybox | /out/busybox sed -n '1p')"
printf '%s\n' "${version_line}"
if ! printf '%s\n' "${version_line}" | grep -Fq "BusyBox v${SOURCE_VERSION}"; then
    echo "error: unexpected BusyBox version" >&2
    exit 1
fi
/out/busybox --list | LC_ALL=C /out/busybox sort > /out/actual-applets.txt
if ! /out/busybox cmp "${expected_applets}" /out/actual-applets.txt; then
    echo "error: BusyBox applet inventory differs from the committed list" >&2
    exit 1
fi

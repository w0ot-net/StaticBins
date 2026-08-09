#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

source_lock="/usr/local/share/static_bins/nc/source.lock"
source_input_dir="/usr/local/share/static_bins/nc/sources"
patch_input_dir="/usr/local/share/static_bins/nc/patches"
patch_lock="${patch_input_dir}/patch.lock"
license_dir="/usr/local/share/licenses/nc"
archive_inventory="${license_dir}/archive-inventory.tsv"
validator="/usr/local/bin/validate-nc-elf"
configure_triplet="arm64-unknown-linux-gnu"
expected_machine="AArch64"

# shellcheck source=source.lock
. "${source_lock}"

: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE in source.lock}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256 in source.lock}"
: "${SOURCE_LICENSE:?missing SOURCE_LICENSE in source.lock}"

# shellcheck source=patches/patch.lock
. "${patch_lock}"
: "${PATCH_1:?missing PATCH_1 in patch.lock}"
: "${PATCH_1_SHA256:?missing PATCH_1_SHA256 in patch.lock}"
: "${PATCH_2:?missing PATCH_2 in patch.lock}"
: "${PATCH_2_SHA256:?missing PATCH_2_SHA256 in patch.lock}"

source_dir="/build/netcat-${SOURCE_VERSION}"
for command_name in awk cc cp file make patch readelf readlink sha256sum sort strip tar; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done
if [ ! -r "${archive_inventory}" ]; then
    echo "error: missing linked-archive inventory: ${archive_inventory}" >&2
    exit 1
fi

mkdir -p /build /out
source_archive="/build/${SOURCE_ARCHIVE}"
cp "${source_input_dir}/${SOURCE_ARCHIVE}" "${source_archive}"
printf '%s  %s\n' "${SOURCE_SHA256}" "${source_archive}" | sha256sum -c -
tar -xf "${source_archive}" -C /build

cd "${source_dir}"
for patch_number in 1 2; do
    eval "patch_name=\${PATCH_${patch_number}}"
    eval "patch_sha256=\${PATCH_${patch_number}_SHA256}"
    source_patch="${patch_input_dir}/${patch_name}"
    printf '%s  %s\n' "${patch_sha256}" "${source_patch}" | sha256sum -c -
    patch --fuzz=0 -p1 < "${source_patch}"
done

if ! CFLAGS="-O2 -pipe"     LDFLAGS="-static -Wl,-Map,/out/nc-link.map"     ./configure         --build="${configure_triplet}"         --host="${configure_triplet}"         --disable-dependency-tracking         --disable-nls > /out/nc-configure.log 2>&1; then
    cat /out/nc-configure.log >&2
    exit 1
fi
if ! make -C src -j"${BUILD_JOBS}" V=1 > /out/nc-link.log 2>&1; then
    cat /out/nc-link.log >&2
    exit 1
fi
tail -n 3 /out/nc-link.log

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
' /out/nc-link.map | sort -u > /out/linked-archives.raw

: > /out/linked-archives.txt
: > /out/matched-inventory.txt
inventory_errors=0
while IFS= read -r linked_archive; do
    case "${linked_archive}" in
        /*) archive_path="${linked_archive}" ;;
        *) archive_path="${source_dir}/src/${linked_archive}" ;;
    esac
    archive_path="$(readlink -f "${archive_path}")"
    inventory_row="$(awk -F '\t' -v path="${archive_path}"         '$1 == path { print; found = 1 } END { if (!found) exit 1 }'         "${archive_inventory}")" || {
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
    if [ ! -r "${license_dir}/${license_file}" ] || [ -z "${source_evidence}" ]; then
        echo "error: incomplete license/source evidence for ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    if [ "${origin}" != builder ]; then
        echo "error: unexpected archive origin for nc: ${origin}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
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
done < "${archive_inventory}"

if [ "${inventory_errors}" -ne 0 ]; then
    echo "Linked archives observed in the final map:" >&2
    cat /out/linked-archives.raw >&2
    exit 1
fi

install -m 0755 src/netcat /out/nc
strip /out/nc
"${validator}" /out/nc

version_output="$(/out/nc --version)"
printf '%s\n' "${version_output}"
if ! printf '%s\n' "${version_output}" | grep -Fq     "netcat (The GNU Netcat) ${SOURCE_VERSION}"; then
    echo "error: unexpected GNU Netcat version" >&2
    exit 1
fi

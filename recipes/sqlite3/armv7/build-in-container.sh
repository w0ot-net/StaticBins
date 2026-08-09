#!/bin/sh

set -eu

recipe_dir=/usr/local/share/static_bins/sqlite3
source_lock="${recipe_dir}/source.lock"
target_lock="${recipe_dir}/target.lock"
source_input_dir="${recipe_dir}/sources"
license_dir=/usr/local/share/licenses/sqlite3
archive_inventory="${license_dir}/archive-inventory.tsv"
validator="${recipe_dir}/validate-elf.sh"

. "${source_lock}"
. "${target_lock}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256}"
: "${TARGET_CFLAGS:=}"

target_cflags="-O2 -pipe ${TARGET_CFLAGS}"
source_dir=/build/sqlite-autoconf-3530400
if [ "${TARGET_ARCHITECTURE}" = x86 ] &&
    [ "${TARGET_CFLAGS}" != '-march=i686 -msse2 -mfpmath=sse' ]; then
    echo "error: x86 target must use the repository i686/SSE2 baseline" >&2
    exit 1
fi
for command_name in awk cc cp file grep readelf readlink sed sha256sum sort strip tar; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done

mkdir -p /build /out
source_archive="/build/${SOURCE_ARCHIVE}"
cp "${source_input_dir}/${SOURCE_ARCHIVE}" "${source_archive}"
printf '%s  %s\n' "${SOURCE_SHA256}" "${source_archive}" | sha256sum -c -
tar -xf "${source_archive}" -C /build
cd "${source_dir}"

set -x
cc ${target_cflags} \
    -DSQLITE_THREADSAFE=1 \
    -DSQLITE_DQS=0 \
    -DSQLITE_OMIT_LOAD_EXTENSION \
    -DSQLITE_ENABLE_FTS5 \
    -DSQLITE_ENABLE_DBPAGE_VTAB \
    -DSQLITE_ENABLE_RTREE \
    -DSQLITE_ENABLE_DBSTAT_VTAB \
    -DSQLITE_ENABLE_MATH_FUNCTIONS \
    -DSQLITE_ENABLE_EXPLAIN_COMMENTS \
    -static -Wl,-Map,/tmp/sqlite3-link.map \
    shell.c sqlite3.c -lpthread -lm -o /tmp/sqlite3
set +x

awk '
    $1 == "LOAD" && $2 ~ /[.]a$/ { print $2 }
    {
        line = $0
        while (match(line, /[^[:space:]()]+[.]a[(]/)) {
            print substr(line, RSTART, RLENGTH - 1)
            line = substr(line, RSTART + RLENGTH)
        }
    }
' /tmp/sqlite3-link.map | sort -u > /tmp/linked-archives.raw

tab="$(printf '\t')"
: > /tmp/matched-inventory.txt
inventory_errors=0
while IFS= read -r linked_archive; do
    case "${linked_archive}" in
        /*) archive_path="${linked_archive}" ;;
        *) archive_path="${source_dir}/${linked_archive}" ;;
    esac
    archive_path="$(readlink -f "${archive_path}")"
    if ! awk -F '\t' -v path="${archive_path}" \
        '$1 == path { found = 1 } END { if (!found) exit 1 }' \
        "${archive_inventory}"; then
        echo "error: linked archive is not inventoried: ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    printf '%s\n' "${archive_path}" >> /tmp/matched-inventory.txt
done < /tmp/linked-archives.raw

while IFS="${tab}" read -r archive_path origin package version license license_file source_evidence; do
    case "${archive_path}" in "" | \#*) continue ;; esac
    if ! grep -Fxq "${archive_path}" /tmp/matched-inventory.txt; then
        echo "error: inventoried archive was not linked: ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    if [ "${origin}" != builder ] || [ -z "${package}" ] || [ -z "${version}" ] ||
        [ -z "${license}" ] || [ ! -r "${license_dir}/${license_file}" ] ||
        [ -z "${source_evidence}" ]; then
        echo "error: incomplete linked-input evidence for ${archive_path}" >&2
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
    echo "Linked archives observed in the SQLite map:" >&2
    cat /tmp/linked-archives.raw >&2
    exit 1
fi

install -m 0755 /tmp/sqlite3 /out/sqlite3
strip /out/sqlite3
"${validator}" /out/sqlite3

version_output="$(/out/sqlite3 --version)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | awk '{print $1}')" != \
    "${SOURCE_VERSION}" ]; then
    echo "error: unexpected SQLite version" >&2
    exit 1
fi

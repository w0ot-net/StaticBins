#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

source_lock="/usr/local/share/static_bins/rsync/source.lock"
source_input_dir="/usr/local/share/static_bins/rsync/sources"
license_dir="/usr/local/share/licenses/rsync"
archive_inventory="${license_dir}/archive-inventory.tsv"
object_inventory="${license_dir}/bundled-object-inventory.tsv"
validator="/usr/local/bin/validate-rsync-elf"
target_cflags="-O2 -pipe"

# shellcheck source=source.lock
. "${source_lock}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE in source.lock}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256 in source.lock}"
: "${SOURCE_LICENSE:?missing SOURCE_LICENSE in source.lock}"
: "${SOURCE_SIGNATURE:?missing SOURCE_SIGNATURE in source.lock}"
: "${SOURCE_SIGNING_KEY:?missing SOURCE_SIGNING_KEY in source.lock}"
: "${SOURCE_SIGNER_FINGERPRINT:?missing SOURCE_SIGNER_FINGERPRINT in source.lock}"

source_dir="/build/rsync-${SOURCE_VERSION}"
for command_name in awk cc cp file grep make readelf readlink sed sha256sum sort strip tar; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done
if [ ! -r "${archive_inventory}" ] || [ ! -r "${object_inventory}" ]; then
    echo "error: missing rsync linked-input inventory" >&2
    exit 1
fi

mkdir -p /build /out
source_archive="/build/${SOURCE_ARCHIVE}"
cp "${source_input_dir}/${SOURCE_ARCHIVE}" "${source_archive}"
printf '%s  %s\n' "${SOURCE_SHA256}" "${source_archive}" | sha256sum -c -
tar -xf "${source_archive}" -C /build
cd "${source_dir}"

if ! CFLAGS="${target_cflags}" \
    LDFLAGS="-static -Wl,-Map,/out/rsync-link.map" \
    ./configure \
        --disable-md2man \
        --enable-ipv6 \
        --enable-xattr-support \
        --disable-acl-support \
        --disable-iconv \
        --disable-openssl \
        --disable-xxhash \
        --disable-zstd \
        --disable-lz4 \
        --with-included-popt \
        --with-included-zlib \
        > /out/rsync-configure.log 2>&1; then
    tail -n 200 /out/rsync-configure.log >&2
    exit 1
fi
tail -n 35 /out/rsync-configure.log

if ! make -j"${BUILD_JOBS}" V=1 > /out/rsync-build.log 2>&1; then
    tail -n 200 /out/rsync-build.log >&2
    exit 1
fi
tail -n 15 /out/rsync-build.log

link_command="$(grep -E ' -o rsync( |$)' /out/rsync-build.log | tail -n 1)"
if [ -z "${link_command}" ]; then
    echo "error: rsync final link command was not recorded" >&2
    exit 1
fi
tab="$(printf '\t')"
object_errors=0
while IFS="${tab}" read -r object_path package version license license_file source_evidence; do
    case "${object_path}" in "" | \#*) continue ;; esac
    case " ${link_command} " in
        *" ${object_path} "*) ;;
        *)
            echo "error: bundled object was not present in final link: ${object_path}" >&2
            object_errors=$((object_errors + 1))
            ;;
    esac
    if [ -z "${package}" ] || [ -z "${version}" ] || [ -z "${license}" ] ||
        [ ! -r "${license_dir}/${license_file}" ] || [ -z "${source_evidence}" ]; then
        echo "error: incomplete bundled-object evidence for ${object_path}" >&2
        object_errors=$((object_errors + 1))
    fi
done < "${object_inventory}"
if [ "${object_errors}" -ne 0 ]; then
    exit 1
fi
if printf '%s\n' "${link_command}" | grep -Eq \
    '(^|[[:space:]])-l(crypto|ssl|xxhash|zstd|lz4|z|acl)([[:space:]]|$)'; then
    echo "error: disabled or system compression/crypto library entered rsync link" >&2
    exit 1
fi

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
' /out/rsync-link.map | sort -u > /out/linked-archives.raw

: > /out/matched-inventory.txt
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
    printf '%s\n' "${archive_path}" >> /out/matched-inventory.txt
done < /out/linked-archives.raw

while IFS="${tab}" read -r archive_path origin package version license license_file source_evidence; do
    case "${archive_path}" in "" | \#*) continue ;; esac
    if ! grep -Fxq "${archive_path}" /out/matched-inventory.txt; then
        echo "error: inventoried archive was not present in final link: ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    if [ "${origin}" != builder ] || [ -z "${package}" ] || [ -z "${version}" ] ||
        [ -z "${license}" ] || [ ! -r "${license_dir}/${license_file}" ] ||
        [ -z "${source_evidence}" ]; then
        echo "error: incomplete or unexpected archive evidence for ${archive_path}" >&2
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

install -m 0755 rsync /out/rsync
strip /out/rsync
"${validator}" /out/rsync

version_output="$(/out/rsync --version)"
printf '%s\n' "${version_output}"
if ! printf '%s\n' "${version_output}" | grep -Fq \
    "rsync  version ${SOURCE_VERSION}  protocol version 32"; then
    echo "error: unexpected rsync version or protocol" >&2
    exit 1
fi
printf '%s\n' "${version_output}" | tr ',' '\n' | \
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//' > /out/rsync-version-items.txt
for required_item in IPv6 xattrs 'no ACLs' 'no iconv' 'no openssl-crypto'; do
    if ! grep -Fxq "${required_item}" /out/rsync-version-items.txt; then
        echo "error: rsync capability mismatch: ${required_item}" >&2
        exit 1
    fi
done
if ! grep -Fxq 'zlibx zlib none' /out/rsync-version-items.txt ||
    printf '%s\n' "${version_output}" | grep -Eq 'xxh|zstd|lz4'; then
    echo "error: rsync checksum or compression feature mismatch" >&2
    exit 1
fi

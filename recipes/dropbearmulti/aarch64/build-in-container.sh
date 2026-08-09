#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

source_lock="/usr/local/share/static_bins/dropbearmulti/source.lock"
source_input_dir="/usr/local/share/static_bins/dropbearmulti/sources"
localoptions_input="/usr/local/share/static_bins/dropbearmulti/localoptions.h"
license_dir="/usr/local/share/licenses/dropbearmulti"
archive_inventory="${license_dir}/archive-inventory.tsv"
validator="/usr/local/bin/validate-dropbearmulti-elf"
target_cflags="-O2 -pipe"
programs="dropbear dbclient dropbearkey dropbearconvert"

# shellcheck source=source.lock
. "${source_lock}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE in source.lock}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256 in source.lock}"
: "${SOURCE_LICENSE:?missing SOURCE_LICENSE in source.lock}"
: "${SOURCE_AUTHENTICATION:?missing SOURCE_AUTHENTICATION in source.lock}"
: "${SOURCE_SIGNATURE:?missing SOURCE_SIGNATURE in source.lock}"
: "${SOURCE_SIGNING_KEY:?missing SOURCE_SIGNING_KEY in source.lock}"
: "${SOURCE_SIGNER_FINGERPRINT:?missing SOURCE_SIGNER_FINGERPRINT in source.lock}"

if [ "${SOURCE_AUTHENTICATION}" != pgp ]; then
    echo "error: Dropbear source authentication must be pgp" >&2
    exit 1
fi

for command_name in awk cmp cp file grep make readelf readlink sed sha256sum sort strip tar; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done
for required_input in "${localoptions_input}" "${archive_inventory}"; do
    if [ ! -r "${required_input}" ]; then
        echo "error: missing Dropbear recipe input: ${required_input}" >&2
        exit 1
    fi
done

mkdir -p /build /out
source_archive="/build/${SOURCE_ARCHIVE}"
cp "${source_input_dir}/${SOURCE_ARCHIVE}" "${source_archive}"
printf '%s  %s\n' "${SOURCE_SHA256}" "${source_archive}" | sha256sum -c -
tar -xf "${source_archive}" -C /build
source_dir="/build/dropbear-${SOURCE_VERSION}"
cd "${source_dir}"

cp "${localoptions_input}" localoptions.h
cmp "${localoptions_input}" localoptions.h
if [ "$(wc -l < localoptions.h)" -ne 1 ] ||
    ! grep -Fxq '#define DROPBEAR_SFTPSERVER 0' localoptions.h; then
    echo "error: localoptions.h is not the reviewed SFTP-only override" >&2
    exit 1
fi

if ! CFLAGS="${target_cflags}" \
    LDFLAGS="-static -Wl,-Map,/out/dropbearmulti-link.map" \
    ./configure \
        --enable-static \
        --enable-bundled-libtom \
        --disable-zlib \
        > /out/dropbear-configure.log 2>&1; then
    tail -n 200 /out/dropbear-configure.log >&2
    exit 1
fi
tail -n 25 /out/dropbear-configure.log
if ! grep -Fq 'Using bundled libtomcrypt and libtommath' \
    /out/dropbear-configure.log ||
    ! grep -Fxq '#define BUNDLED_LIBTOM 1' config.h ||
    ! grep -Fxq '#define DISABLE_ZLIB 1' config.h; then
    echo "error: Dropbear configure feature selection drifted" >&2
    exit 1
fi

if ! make -j"${BUILD_JOBS}" V=1 PROGRAMS="${programs}" MULTI=1 \
    > /out/dropbear-build.log 2>&1; then
    tail -n 200 /out/dropbear-build.log >&2
    exit 1
fi
tail -n 20 /out/dropbear-build.log

link_command="$(grep -E ' -o dropbearmulti( |$)' /out/dropbear-build.log | tail -n 1)"
if [ -z "${link_command}" ]; then
    echo "error: Dropbear final link command was not recorded" >&2
    exit 1
fi
for required_link_input in \
    libtomcrypt/libtomcrypt.a libtommath/libtommath.a -lcrypt; do
    case " ${link_command} " in
        *" ${required_link_input} "*) ;;
        *)
            echo "error: required Dropbear link input is absent: ${required_link_input}" >&2
            exit 1
            ;;
    esac
done
if printf '%s\n' "${link_command}" | grep -Eq \
    '(^|[[:space:]])-l(z|pam)([[:space:]]|$)|(^|[[:space:]])[^[:space:]]*scp[^[:space:]]*[.]o([[:space:]]|$)'; then
    echo "error: disabled Dropbear dependency or scp object entered the final link" >&2
    exit 1
fi
if ! grep -Fq -- '-DDBMULTI_dropbearconvert' /out/dropbear-build.log ||
    grep -Fq -- '-DDBMULTI_scp' /out/dropbear-build.log; then
    echo "error: Dropbear multi-call program selection drifted" >&2
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
' /out/dropbearmulti-link.map | sort -u > /out/linked-archives.raw

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
            case "${archive_path}:${package}:${version}" in
                "${source_dir}/libtomcrypt/libtomcrypt.a:libtomcrypt:1.18.2" | \
                "${source_dir}/libtommath/libtommath.a:libtommath:1.2.0") ;;
                *)
                    echo "error: wrong bundled source inventory identity: ${archive_path}" >&2
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

install -m 0755 dropbearmulti /out/dropbearmulti
strip /out/dropbearmulti
"${validator}" /out/dropbearmulti

version_output="$(/out/dropbearmulti dbclient -V 2>&1)"
printf '%s\n' "${version_output}"
if [ "${version_output}" != "Dropbear v${SOURCE_VERSION}" ] ||
    [ "$(/out/dropbearmulti dropbear -V 2>&1)" != "Dropbear v${SOURCE_VERSION}" ]; then
    echo "error: unexpected Dropbear version" >&2
    exit 1
fi

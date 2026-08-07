#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

source_lock="/usr/local/share/static_bins/lsof/source.lock"
source_input_dir="/usr/local/share/static_bins/lsof/sources"
license_dir="/usr/local/share/licenses/lsof"
archive_inventory="${license_dir}/archive-inventory.tsv"
target_triplet="i586-alpine-linux-musl"
expected_machine="Intel 80386"

if [ ! -r "${source_lock}" ]; then
    echo "error: missing lsof source lock: ${source_lock}" >&2
    exit 1
fi

# shellcheck source=source.lock
. "${source_lock}"

: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE in source.lock}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256 in source.lock}"
: "${SOURCE_UPSTREAM_URL:?missing SOURCE_UPSTREAM_URL in source.lock}"
: "${SOURCE_LICENSE:?missing SOURCE_LICENSE in source.lock}"

case "${SOURCE_ARCHIVE}" in
    */* | "")
        echo "error: SOURCE_ARCHIVE must be a filename" >&2
        exit 1
        ;;
esac

source_dir="/build/lsof-${SOURCE_VERSION}"
build_dir="/build/lsof-build"

for command_name in cc cp file make pkg-config readelf sha256sum strip tar; do
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
cd /build

source_input="${source_input_dir}/${SOURCE_ARCHIVE}"
source_archive="/build/${SOURCE_ARCHIVE}"
if [ ! -f "${source_input}" ]; then
    echo "error: missing tracked lsof source archive: ${source_input}" >&2
    exit 1
fi
cp "${source_input}" "${source_archive}"
echo "${SOURCE_SHA256}  ${source_archive}" | sha256sum -c -

tar -xf "${source_archive}"
mkdir -p "${build_dir}"
cd "${build_dir}"

libtirpc_cflags="$(pkg-config --cflags libtirpc-nokrb)"
libtirpc_libs="$(pkg-config --libs --static libtirpc-nokrb)"
if [ "${libtirpc_libs}" != "-ltirpc-nokrb -lpthread" ]; then
    echo "error: unexpected libtirpc-nokrb static link flags: ${libtirpc_libs}" >&2
    exit 1
fi

CFLAGS="-O2 -pipe -march=i686 -msse2 -mfpmath=sse" \
LDFLAGS="-static -no-pie" \
LIBTIRPC_CFLAGS="${libtirpc_cflags}" \
LIBTIRPC_LIBS="${libtirpc_libs}" \
"${source_dir}/configure" \
    --build="${target_triplet}" \
    --host="${target_triplet}" \
    --prefix=/usr \
    --disable-liblsof \
    --disable-shared \
    --enable-static \
    --with-libtirpc \
    --without-selinux

if ! make -j"${BUILD_JOBS}" V=1 \
    LDFLAGS="-all-static -no-pie -Wl,-Map,/out/lsof-link.map" \
    lsof > /out/lsof-link.log 2>&1; then
    cat /out/lsof-link.log >&2
    exit 1
fi
tail -n 2 /out/lsof-link.log

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
' /out/lsof-link.map | sort -u > /out/linked-archives.raw

: > /out/linked-archives.txt
: > /out/matched-inventory.txt
inventory_errors=0
while IFS= read -r linked_archive; do
    case "${linked_archive}" in
        /*) archive_path="${linked_archive}" ;;
        *) archive_path="${build_dir}/${linked_archive}" ;;
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
while IFS="${tab}" read -r archive_path package version license license_file aports_source; do
    case "${archive_path}" in "" | \#*) continue ;; esac

    if ! grep -Fxq "${archive_path}" /out/matched-inventory.txt; then
        echo "error: inventoried archive was not present in the final link: ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    if [ ! -r "${license_dir}/${license_file}" ]; then
        echo "error: missing license material for ${archive_path}: ${license_file}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    if [ -z "${license}" ] || [ -z "${aports_source}" ]; then
        echo "error: incomplete inventory row for ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi

    installed_owner="$(apk info -W "${archive_path}" | sed 's/.* is owned by //')"
    if [ "${installed_owner}" != "${package}-${version}" ]; then
        echo "error: ${archive_path}: expected ${package}-${version}, found ${installed_owner}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
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

install -m 0755 lsof /out/lsof
strip /out/lsof

if ! file /out/lsof | grep -Eq 'ELF 32-bit LSB executable, Intel (i386|80386)'; then
    echo "error: lsof is not a 32-bit little-endian x86 executable" >&2
    exit 1
fi
if ! readelf -h /out/lsof | grep -Eq 'Class:[[:space:]]+ELF32'; then
    echo "error: lsof is not ELF32" >&2
    exit 1
fi
if ! readelf -h /out/lsof | grep -Eq "Data:[[:space:]]+2's complement, little endian"; then
    echo "error: lsof is not little-endian" >&2
    exit 1
fi
if ! readelf -h /out/lsof | grep -Eq "Machine:[[:space:]]+${expected_machine}"; then
    echo "error: lsof has the wrong ELF machine" >&2
    readelf -h /out/lsof >&2
    exit 1
fi
if ! readelf -h /out/lsof | grep -Eq 'Type:[[:space:]]+EXEC'; then
    echo "error: lsof is not an ELF ET_EXEC executable" >&2
    exit 1
fi
if readelf -l /out/lsof | grep -q 'Requesting program interpreter'; then
    echo "error: lsof has a dynamic program interpreter" >&2
    exit 1
fi
if readelf -d /out/lsof 2>/dev/null | grep -q '(NEEDED)'; then
    echo "error: lsof has dynamic library dependencies" >&2
    readelf -d /out/lsof | grep '(NEEDED)' >&2
    exit 1
fi
if readelf -S /out/lsof | grep -Eq '[.]debug|[.]symtab'; then
    echo "error: lsof retains debug or full symbol-table sections" >&2
    exit 1
fi

version_output="$(/out/lsof -v 2>&1)"
printf '%s\n' "${version_output}"
if ! printf '%s\n' "${version_output}" | grep -Eq "^[[:space:]]*revision: ${SOURCE_VERSION}$"; then
    echo "error: unexpected lsof version" >&2
    exit 1
fi
features="$(printf '%s\n' "${version_output}" | sed -n 's/^[[:space:]]*features enabled: //p')"
for feature in ipv6 ptyept rpc soopt sostate tasks uxsockept; do
    case " ${features} " in
        *" ${feature} "*) ;;
        *)
            echo "error: lsof is missing expected feature: ${feature}" >&2
            exit 1
            ;;
    esac
done
if ! printf '%s\n' "${version_output}" | grep -Fq 'Anyone can list all files.'; then
    echo "error: lsof has an unexpected security restriction" >&2
    exit 1
fi

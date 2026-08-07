#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

source_lock="/usr/local/share/static_bins/gdb/source.lock"
license_dir="/usr/local/share/licenses/gdb"
archive_inventory="${license_dir}/archive-inventory.tsv"

if [ ! -r "${source_lock}" ]; then
    echo "error: missing GDB source lock: ${source_lock}" >&2
    exit 1
fi

# shellcheck source=source.lock
. "${source_lock}"

: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE in source.lock}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256 in source.lock}"
: "${SOURCE_UPSTREAM_URL:?missing SOURCE_UPSTREAM_URL in source.lock}"
: "${SOURCE_RELEASE_TAG:?missing SOURCE_RELEASE_TAG in source.lock}"
: "${SOURCE_MIRROR_URL:?missing SOURCE_MIRROR_URL in source.lock}"
: "${SOURCE_LICENSE:?missing SOURCE_LICENSE in source.lock}"

case "${SOURCE_ARCHIVE}" in
    */* | "")
        echo "error: SOURCE_ARCHIVE must be a filename" >&2
        exit 1
        ;;
esac

source_dir="/build/gdb-${SOURCE_VERSION}"
build_dir="/build/gdb-build"

for command_name in cc c++ make wget tar sha256sum file readelf strip; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done

for archive_path in \
    /usr/lib/libc.a \
    /usr/lib/libexpat.a \
    /usr/lib/libgmp.a \
    /usr/lib/libmpfr.a \
    /usr/lib/libncursesw.a \
    /usr/lib/liblzma.a \
    /usr/lib/libz.a \
    /usr/lib/libzstd.a; do
    if [ ! -f "${archive_path}" ]; then
        echo "error: locked builder is missing ${archive_path}" >&2
        exit 1
    fi
done

if [ ! -r "${archive_inventory}" ]; then
    echo "error: missing linked-archive inventory: ${archive_inventory}" >&2
    exit 1
fi

mkdir -p /build /out
cd /build

source_candidate="/build/${SOURCE_ARCHIVE}.part"
source_archive="/build/${SOURCE_ARCHIVE}"
source_found=false

for source_url in "${SOURCE_MIRROR_URL}" "${SOURCE_UPSTREAM_URL}"; do
    rm -f "${source_candidate}"
    echo "Fetching ${SOURCE_ARCHIVE} from ${source_url}"
    if ! wget -q --timeout=30 --tries=3 -O "${source_candidate}" "${source_url}"; then
        echo "warning: source fetch failed: ${source_url}" >&2
        continue
    fi

    if ! echo "${SOURCE_SHA256}  ${source_candidate}" | sha256sum -c -; then
        echo "warning: source checksum rejected: ${source_url}" >&2
        continue
    fi

    mv "${source_candidate}" "${source_archive}"
    source_found=true
    break
done

rm -f "${source_candidate}"

if [ "${source_found}" != true ]; then
    echo "error: no approved source URL supplied ${SOURCE_ARCHIVE} with the locked checksum" >&2
    exit 1
fi

tar -xf "${source_archive}"
mkdir -p "${build_dir}"
cd "${build_dir}"

CFLAGS="-O2 -pipe" \
CXXFLAGS="-O2 -pipe" \
LDFLAGS="-static" \
LIBS="-lm -pthread" \
"${source_dir}/configure" \
    --build=aarch64-alpine-linux-musl \
    --host=aarch64-alpine-linux-musl \
    --target=aarch64-alpine-linux-musl \
    --prefix=/usr \
    --disable-binutils \
    --disable-gas \
    --disable-gold \
    --disable-gprof \
    --disable-ld \
    --disable-nls \
    --disable-shared \
    --disable-sim \
    --disable-source-highlight \
    --disable-werror \
    --enable-static \
    --with-curses \
    --with-expat \
    --with-libexpat-type=static \
    --with-system-zlib \
    --with-liblzma-type=static \
    --with-lzma \
    --with-zstd \
    --without-babeltrace \
    --without-debuginfod \
    --without-guile \
    --without-intel-pt \
    --without-python

make -j"${BUILD_JOBS}" all-gdb

# GDB links through GNU libtool. In libtool, -static only selects static
# libtool archives; -all-static is what passes -static to the compiler driver.
rm -f gdb/gdb
if ! make -C gdb V=1 LDFLAGS="-all-static -Wl,-Map,/out/gdb-link.map" gdb \
    > /out/gdb-link.log 2>&1; then
    cat /out/gdb-link.log >&2
    exit 1
fi
cat /out/gdb-link.log

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
' /out/gdb-link.map | sort -u > /out/linked-archives.raw

: > /out/linked-archives.txt
: > /out/matched-inventory.txt
internal_archive_count=0
inventory_errors=0
while IFS= read -r linked_archive; do
    case "${linked_archive}" in
        /*) archive_path="${linked_archive}" ;;
        *) archive_path="${build_dir}/gdb/${linked_archive}" ;;
    esac
    archive_path="$(readlink -f "${archive_path}")"

    case "${archive_path}" in
        "${build_dir}"/* | "${source_dir}"/*)
            printf 'gdb-source\t%s\t%s\t%s\n' \
                "${SOURCE_VERSION}" "${SOURCE_LICENSE}" "${archive_path}" \
                >> /out/linked-archives.txt
            internal_archive_count=$((internal_archive_count + 1))
            ;;
        *)
            inventory_row="$(awk -F '\t' -v path="${archive_path}" \
                '$1 == path { print; found = 1 } END { if (!found) exit 1 }' \
                "${archive_inventory}")" || {
                    echo "error: linked archive is not inventoried: ${archive_path}" >&2
                    inventory_errors=$((inventory_errors + 1))
                    continue
                }
            printf '%s\n' "${inventory_row}" >> /out/linked-archives.txt
            printf '%s\n' "${archive_path}" >> /out/matched-inventory.txt
            ;;
    esac
done < /out/linked-archives.raw

if [ "${internal_archive_count}" -eq 0 ]; then
    echo "error: final link map contained no GDB-source archives" >&2
    inventory_errors=$((inventory_errors + 1))
fi

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

install -m 0755 gdb/gdb /out/gdb
strip /out/gdb

file /out/gdb

if ! readelf -h /out/gdb | grep -Eq 'Machine:[[:space:]]+AArch64'; then
    echo "error: GDB is not an AArch64 executable" >&2
    readelf -h /out/gdb >&2
    exit 1
fi

if readelf -l /out/gdb | grep -q 'Requesting program interpreter'; then
    echo "error: GDB has a dynamic program interpreter" >&2
    exit 1
fi

if readelf -d /out/gdb 2>/dev/null | grep -q '(NEEDED)'; then
    echo "error: GDB has dynamic library dependencies" >&2
    readelf -d /out/gdb | grep '(NEEDED)' >&2
    exit 1
fi

/out/gdb --batch --version

#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

source_lock="/usr/local/share/static_bins/gdbserver/source.lock"
source_input_dir="/usr/local/share/static_bins/gdbserver/sources"
license_dir="/usr/local/share/licenses/gdbserver"
archive_inventory="${license_dir}/archive-inventory.tsv"
target_triplet="aarch64-alpine-linux-musl"
expected_machine="AArch64"

if [ ! -r "${source_lock}" ]; then
    echo "error: missing GDBserver source lock: ${source_lock}" >&2
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

source_dir="/build/gdb-${SOURCE_VERSION}"
build_dir="/build/gdbserver-build"

for command_name in cc c++ cp make tar sha256sum file readelf strip; do
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
    echo "error: missing tracked GDB source archive: ${source_input}" >&2
    exit 1
fi
cp "${source_input}" "${source_archive}"
echo "${SOURCE_SHA256}  ${source_archive}" | sha256sum -c -

tar -xf "${source_archive}"
mkdir -p "${build_dir}"
cd "${build_dir}"

CFLAGS="-O2 -pipe" \
CXXFLAGS="-O2 -pipe" \
LDFLAGS="-static -no-pie" \
"${source_dir}/configure" \
    --build="${target_triplet}" \
    --host="${target_triplet}" \
    --target="${target_triplet}" \
    --prefix=/usr \
    --disable-binutils \
    --disable-gas \
    --disable-gdb \
    --disable-gdbtk \
    --disable-gold \
    --disable-gprof \
    --disable-inprocess-agent \
    --disable-ld \
    --disable-nls \
    --disable-rpath \
    --disable-shared \
    --disable-sim \
    --disable-source-highlight \
    --disable-werror \
    --enable-static \
    --with-expat \
    --with-libexpat-type=static \
    --without-babeltrace \
    --without-debuginfod \
    --without-guile \
    --without-python

make -j"${BUILD_JOBS}" all-gdbserver

rm -f gdbserver/gdbserver
if ! make -C gdbserver V=1 \
    LDFLAGS="-static -no-pie -Wl,-Map,/out/gdbserver-link.map" gdbserver \
    > /out/gdbserver-link.log 2>&1; then
    cat /out/gdbserver-link.log >&2
    exit 1
fi
cat /out/gdbserver-link.log

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
' /out/gdbserver-link.map | sort -u > /out/linked-archives.raw

: > /out/linked-archives.txt
: > /out/matched-inventory.txt
internal_archive_count=0
inventory_errors=0
while IFS= read -r linked_archive; do
    case "${linked_archive}" in
        /*) archive_path="${linked_archive}" ;;
        *) archive_path="${build_dir}/gdbserver/${linked_archive}" ;;
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

install -m 0755 gdbserver/gdbserver /out/gdbserver
strip /out/gdbserver

file /out/gdbserver
if ! readelf -h /out/gdbserver | grep -Eq "Machine:[[:space:]]+${expected_machine}"; then
    echo "error: GDBserver has the wrong ELF machine" >&2
    readelf -h /out/gdbserver >&2
    exit 1
fi
if ! readelf -h /out/gdbserver | grep -Eq 'Type:[[:space:]]+EXEC'; then
    echo "error: GDBserver is not an ELF ET_EXEC executable" >&2
    exit 1
fi
if readelf -l /out/gdbserver | grep -q 'Requesting program interpreter'; then
    echo "error: GDBserver has a dynamic program interpreter" >&2
    exit 1
fi
if readelf -d /out/gdbserver 2>/dev/null | grep -q '(NEEDED)'; then
    echo "error: GDBserver has dynamic library dependencies" >&2
    readelf -d /out/gdbserver | grep '(NEEDED)' >&2
    exit 1
fi
if readelf -S /out/gdbserver | grep -Eq '[.]debug|[.]symtab'; then
    echo "error: GDBserver retains debug or full symbol-table sections" >&2
    exit 1
fi

/out/gdbserver --version

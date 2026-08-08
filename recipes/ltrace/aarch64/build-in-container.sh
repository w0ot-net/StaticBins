#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

source_lock="/usr/local/share/static_bins/ltrace/source.lock"
source_input_dir="/usr/local/share/static_bins/ltrace/sources"
source_patch="/usr/local/share/static_bins/ltrace/musl-main-link-map.patch"
aarch64_patch="/usr/local/share/static_bins/ltrace/aarch64-musl-pid-t.patch"
license_dir="/usr/local/share/licenses/ltrace"
archive_inventory="${license_dir}/archive-inventory.tsv"
target_triplet="aarch64-alpine-linux-musl"
expected_machine="AArch64"

if [ ! -r "${source_lock}" ]; then
    echo "error: missing ltrace source lock: ${source_lock}" >&2
    exit 1
fi

# shellcheck source=source.lock
. "${source_lock}"

: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE in source.lock}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256 in source.lock}"
: "${SOURCE_UPSTREAM_URL:?missing SOURCE_UPSTREAM_URL in source.lock}"
: "${SOURCE_LICENSE:?missing SOURCE_LICENSE in source.lock}"
: "${SOURCE_AUTHENTICATION:?missing SOURCE_AUTHENTICATION in source.lock}"

case "${SOURCE_ARCHIVE}" in
    */* | "")
        echo "error: SOURCE_ARCHIVE must be a filename" >&2
        exit 1
        ;;
esac
if [ "${SOURCE_AUTHENTICATION}" != "checksum-only" ]; then
    echo "error: unsupported ltrace source authentication mode" >&2
    exit 1
fi

source_dir="/build/ltrace-${SOURCE_VERSION}"

for command_name in \
    apk autoreconf awk cc cp file grep make patch readelf readlink \
    sha256sum sort strip tar; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done
for required_input in \
    "${archive_inventory}" "${source_patch}" "${aarch64_patch}"; do
    if [ ! -r "${required_input}" ]; then
        echo "error: missing recipe input: ${required_input}" >&2
        exit 1
    fi
done

mkdir -p /build /out
cd /build

source_input="${source_input_dir}/${SOURCE_ARCHIVE}"
source_archive="/build/${SOURCE_ARCHIVE}"
if [ ! -f "${source_input}" ]; then
    echo "error: missing tracked ltrace source archive: ${source_input}" >&2
    exit 1
fi
cp "${source_input}" "${source_archive}"
echo "${SOURCE_SHA256}  ${source_archive}" | sha256sum -c -

tar -xf "${source_archive}"
cd "${source_dir}"
patch -p1 < "${source_patch}"
patch -p1 < "${aarch64_patch}"
autoreconf -fi

if ! CFLAGS="-O2 -pipe" \
    LIBS="-lzstd -lz" \
    ./configure \
        --build="${target_triplet}" \
        --host="${target_triplet}" \
        --prefix=/usr \
        --disable-werror \
        --without-elfutils \
        --without-libunwind > /out/ltrace-configure.log 2>&1; then
    cat /out/ltrace-configure.log >&2
    exit 1
fi
tail -n 3 /out/ltrace-configure.log

if ! make -j"${BUILD_JOBS}" LDFLAGS=-all-static \
    > /out/ltrace-build.log 2>&1; then
    cat /out/ltrace-build.log >&2
    exit 1
fi

# Relink only the completed executable to obtain final-link provenance. The
# compiled objects and archives remain intact, so this does not repeat the
# expensive compilation.
rm -f ltrace
if ! make LDFLAGS="-all-static -Wl,-Map,/out/ltrace-link.map" ltrace \
    >> /out/ltrace-build.log 2>&1; then
    cat /out/ltrace-build.log >&2
    exit 1
fi
tail -n 3 /out/ltrace-build.log

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
' /out/ltrace-link.map | sort -u > /out/linked-archives.raw

: > /out/linked-archives.txt
: > /out/matched-inventory.txt
internal_archive_count=0
inventory_errors=0
while IFS= read -r linked_archive; do
    case "${linked_archive}" in
        /*) archive_path="${linked_archive}" ;;
        *) archive_path="${source_dir}/${linked_archive}" ;;
    esac
    archive_path="$(readlink -f "${archive_path}")"

    case "${archive_path}" in
        "${source_dir}"/*)
            printf 'ltrace-source\t%s\t%s\t%s\n' \
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
    echo "error: final link map contained no ltrace-source archive" >&2
    inventory_errors=$((inventory_errors + 1))
fi

tab="$(printf '\t')"
while IFS="${tab}" read -r \
    archive_path package version license license_file aports_source; do
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

install -m 0755 ltrace /out/ltrace
strip /out/ltrace

file /out/ltrace
if ! file /out/ltrace | grep -q 'static-pie linked'; then
    echo "error: ltrace is not reported as static PIE" >&2
    exit 1
fi
if ! readelf -hW /out/ltrace | grep -Eq \
    "Machine:[[:space:]]+${expected_machine}"; then
    echo "error: ltrace has the wrong ELF machine" >&2
    readelf -hW /out/ltrace >&2
    exit 1
fi
if ! readelf -hW /out/ltrace | grep -Eq \
    'Type:[[:space:]]+DYN .*Position-Independent Executable'; then
    echo "error: ltrace is not an ELF static PIE" >&2
    exit 1
fi
if ! readelf -hW /out/ltrace | grep -Eq \
    'Entry point address:[[:space:]]+0x[1-9a-fA-F][0-9a-fA-F]*'; then
    echo "error: ltrace has no executable entry point" >&2
    exit 1
fi
if readelf -lW /out/ltrace | grep -q 'Requesting program interpreter'; then
    echo "error: ltrace has a dynamic program interpreter" >&2
    exit 1
fi
if readelf -dW /out/ltrace 2>/dev/null | grep -q '(NEEDED)'; then
    echo "error: ltrace has dynamic library dependencies" >&2
    readelf -dW /out/ltrace | grep '(NEEDED)' >&2
    exit 1
fi
if ! readelf -dW /out/ltrace | grep -Eq '\(FLAGS_1\).*PIE'; then
    echo "error: ltrace ET_DYN output is not marked PIE" >&2
    exit 1
fi
if readelf -dW /out/ltrace | grep -q '(TEXTREL)'; then
    echo "error: ltrace static PIE contains text relocations" >&2
    exit 1
fi
if readelf -SW /out/ltrace | grep -Eq '[.]debug|[.]symtab'; then
    echo "error: ltrace retains debug or full symbol-table sections" >&2
    exit 1
fi

version_output="$(/out/ltrace --version 2>&1)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | sed -n '1p')" != \
    "ltrace ${SOURCE_VERSION}" ]; then
    echo "error: unexpected ltrace version" >&2
    exit 1
fi

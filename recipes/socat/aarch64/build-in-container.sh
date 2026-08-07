#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"
export SOURCE_DATE_EPOCH=1782453234

source_lock="/usr/local/share/static_bins/socat/source.lock"
source_input_dir="/usr/local/share/static_bins/socat/sources"
license_dir="/usr/local/share/licenses/socat"
archive_inventory="${license_dir}/archive-inventory.tsv"
target_triplet="aarch64-alpine-linux-musl"
expected_machine="AArch64"

if [ ! -r "${source_lock}" ]; then
    echo "error: missing socat source lock: ${source_lock}" >&2
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

source_dir="/build/socat-${SOURCE_VERSION}"
build_dir="/build/socat-build"

for command_name in autoreconf cc cp file make readelf sha256sum strip tar; do
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
    echo "error: missing tracked socat source archive: ${source_input}" >&2
    exit 1
fi
cp "${source_input}" "${source_archive}"
echo "${SOURCE_SHA256}  ${source_archive}" | sha256sum -c -

tar -xf "${source_archive}"
cd "${source_dir}"
if ! autoreconf -fi > /out/socat-autoreconf.log 2>&1; then
    cat /out/socat-autoreconf.log >&2
    exit 1
fi

mkdir -p "${build_dir}"
cd "${build_dir}"
if ! CFLAGS="-O2 -pipe" \
    LDFLAGS="-static -no-pie -Wl,-Map,/out/socat-link.map" \
    "${source_dir}/configure" \
        --build="${target_triplet}" \
        --host="${target_triplet}" \
        --prefix=/usr \
        --enable-openssl \
        --enable-sctp \
        --disable-readline \
        --disable-libwrap \
        --disable-fips > /out/socat-configure.log 2>&1; then
    cat /out/socat-configure.log >&2
    exit 1
fi
tail -n 3 /out/socat-configure.log

if ! make -j"${BUILD_JOBS}" socat > /out/socat-link.log 2>&1; then
    cat /out/socat-link.log >&2
    exit 1
fi
tail -n 2 /out/socat-link.log

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
' /out/socat-link.map | sort -u > /out/linked-archives.raw

: > /out/linked-archives.txt
: > /out/matched-inventory.txt
internal_archive_count=0
inventory_errors=0
while IFS= read -r linked_archive; do
    case "${linked_archive}" in
        /*) archive_path="${linked_archive}" ;;
        *) archive_path="${build_dir}/${linked_archive}" ;;
    esac
    archive_path="$(readlink -f "${archive_path}")"

    case "${archive_path}" in
        "${build_dir}"/* | "${source_dir}"/*)
            printf 'socat-source\t%s\t%s\t%s\n' \
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
    echo "error: final link map contained no socat-source archive" >&2
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

install -m 0755 socat /out/socat
strip /out/socat

file /out/socat
if ! readelf -h /out/socat | grep -Eq "Machine:[[:space:]]+${expected_machine}"; then
    echo "error: socat has the wrong ELF machine" >&2
    readelf -h /out/socat >&2
    exit 1
fi
if ! readelf -h /out/socat | grep -Eq 'Type:[[:space:]]+EXEC'; then
    echo "error: socat is not an ELF ET_EXEC executable" >&2
    exit 1
fi
if readelf -l /out/socat | grep -q 'Requesting program interpreter'; then
    echo "error: socat has a dynamic program interpreter" >&2
    exit 1
fi
if readelf -d /out/socat 2>/dev/null | grep -q '(NEEDED)'; then
    echo "error: socat has dynamic library dependencies" >&2
    readelf -d /out/socat | grep '(NEEDED)' >&2
    exit 1
fi
if readelf -S /out/socat | grep -Eq '[.]debug|[.]symtab'; then
    echo "error: socat retains debug or full symbol-table sections" >&2
    exit 1
fi

version_output="$(/out/socat -V 2>&1)"
printf '%s\n' "${version_output}"
if ! printf '%s\n' "${version_output}" | grep -Eq \
    "^socat version ${SOURCE_VERSION} on "; then
    echo "error: unexpected socat version" >&2
    exit 1
fi

feature_errors=0
for feature in \
    WITH_STDIO WITH_FDNUM WITH_FILE WITH_CREAT WITH_GOPEN WITH_TERMIOS \
    WITH_PIPE WITH_UNIX WITH_ABSTRACT_UNIXSOCKET WITH_IP4 WITH_IP6 \
    WITH_RAWIP WITH_GENERICSOCKET WITH_INTERFACE WITH_TCP WITH_UDP \
    WITH_SCTP WITH_LISTEN WITH_SOCKS4 WITH_SOCKS4A WITH_VSOCK \
    WITH_PROXY WITH_SYSTEM WITH_EXEC WITH_TUN WITH_PTY WITH_OPENSSL \
    WITH_SYCLS WITH_FILAN WITH_RETRY; do
    if ! printf '%s\n' "${version_output}" | grep -Eq "^  #define ${feature} ([[:alnum:]_]+)$"; then
        echo "error: socat is missing expected feature: ${feature}" >&2
        feature_errors=$((feature_errors + 1))
    fi
done
for feature in WITH_READLINE WITH_LIBWRAP WITH_FIPS; do
    if printf '%s\n' "${version_output}" | grep -Eq "^  #define ${feature} ([[:alnum:]_]+)$"; then
        echo "error: socat unexpectedly enabled feature: ${feature}" >&2
        feature_errors=$((feature_errors + 1))
    fi
done
if [ "${feature_errors}" -ne 0 ]; then
    exit 1
fi

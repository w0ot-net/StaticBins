#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

source_lock="/usr/local/share/static_bins/tcpdump/source.lock"
license_dir="/usr/local/share/licenses/tcpdump"
archive_inventory="${license_dir}/archive-inventory.tsv"

if [ ! -r "${source_lock}" ]; then
    echo "error: missing tcpdump source lock: ${source_lock}" >&2
    exit 1
fi

# shellcheck source=source.lock
. "${source_lock}"

for source_field in \
    SOURCE_VERSION SOURCE_ARCHIVE SOURCE_SHA256 SOURCE_UPSTREAM_URL \
    SOURCE_RELEASE_TAG SOURCE_MIRROR_URL SOURCE_LICENSE LIBPCAP_VERSION \
    LIBPCAP_ARCHIVE LIBPCAP_SHA256 LIBPCAP_UPSTREAM_URL LIBPCAP_MIRROR_URL \
    LIBPCAP_LICENSE; do
    eval "source_value=\${${source_field}:-}"
    if [ -z "${source_value}" ]; then
        echo "error: missing ${source_field} in source.lock" >&2
        exit 1
    fi
done

for source_archive_name in "${SOURCE_ARCHIVE}" "${LIBPCAP_ARCHIVE}"; do
    case "${source_archive_name}" in
        */* | "")
            echo "error: source archive must be a filename: ${source_archive_name}" >&2
            exit 1
            ;;
    esac
done

for command_name in apk awk cc file grep make readelf readlink sed sha256sum sort strip tar wget; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done

for archive_path in \
    /usr/lib/libc.a \
    /usr/lib/libssp_nonshared.a \
    /usr/lib/gcc/x86_64-alpine-linux-musl/15.2.0/libgcc.a \
    /usr/lib/gcc/x86_64-alpine-linux-musl/15.2.0/libgcc_eh.a; do
    if [ ! -f "${archive_path}" ]; then
        echo "error: locked builder is missing ${archive_path}" >&2
        exit 1
    fi
done

if [ ! -r "${archive_inventory}" ]; then
    echo "error: missing linked-archive inventory: ${archive_inventory}" >&2
    exit 1
fi

build_root="/build"
prefix="${build_root}/prefix"
libpcap_source="${build_root}/libpcap-${LIBPCAP_VERSION}"
libpcap_build="${build_root}/libpcap-build"
tcpdump_source="${build_root}/tcpdump-${SOURCE_VERSION}"
tcpdump_build="${build_root}/tcpdump-build"

mkdir -p "${build_root}" "${prefix}" /out

fetch_source() {
    archive_name="$1"
    archive_sha256="$2"
    mirror_url="$3"
    upstream_url="$4"
    candidate="${build_root}/${archive_name}.part"
    destination="${build_root}/${archive_name}"
    source_found=false

    for source_url in "${mirror_url}" "${upstream_url}"; do
        rm -f -- "${candidate}"
        echo "Fetching ${archive_name} from ${source_url}"
        if ! wget -q --timeout=30 --tries=3 -O "${candidate}" "${source_url}"; then
            echo "warning: source fetch failed: ${source_url}" >&2
            continue
        fi
        if ! echo "${archive_sha256}  ${candidate}" | sha256sum -c -; then
            echo "warning: source checksum rejected: ${source_url}" >&2
            continue
        fi
        mv -- "${candidate}" "${destination}"
        source_found=true
        break
    done
    rm -f -- "${candidate}"

    if [ "${source_found}" != true ]; then
        echo "error: no approved URL supplied ${archive_name} with the locked checksum" >&2
        exit 1
    fi
}

fetch_source "${LIBPCAP_ARCHIVE}" "${LIBPCAP_SHA256}" \
    "${LIBPCAP_MIRROR_URL}" "${LIBPCAP_UPSTREAM_URL}"
fetch_source "${SOURCE_ARCHIVE}" "${SOURCE_SHA256}" \
    "${SOURCE_MIRROR_URL}" "${SOURCE_UPSTREAM_URL}"

tar -xf "${build_root}/${LIBPCAP_ARCHIVE}" -C "${build_root}"
tar -xf "${build_root}/${SOURCE_ARCHIVE}" -C "${build_root}"

mkdir -p "${libpcap_build}"
cd "${libpcap_build}"
CFLAGS="-O2 -pipe" \
LDFLAGS="-static -no-pie" \
"${libpcap_source}/configure" \
    --prefix="${prefix}" \
    --disable-shared \
    --disable-remote \
    --disable-usb \
    --disable-netmap \
    --disable-bluetooth \
    --disable-dbus \
    --disable-rdma \
    --without-libnl \
    --without-dag \
    --without-septel \
    --without-snf \
    --without-turbocap \
    --without-dpdk
make -j"${BUILD_JOBS}"
make install

mkdir -p "${tcpdump_build}"
cd "${tcpdump_build}"
PATH="${prefix}/bin:${PATH}" \
CFLAGS="-O2 -pipe" \
CPPFLAGS="-I${prefix}/include" \
LDFLAGS="-static -no-pie -L${prefix}/lib -Wl,-Map=/out/tcpdump-link.map" \
"${tcpdump_source}/configure" \
    --disable-local-libpcap \
    --without-smi \
    --without-crypto \
    --without-cap-ng \
    --without-sandbox-capsicum

if ! make -j"${BUILD_JOBS}" V=1 > /out/tcpdump-build.log 2>&1; then
    cat /out/tcpdump-build.log >&2
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
' /out/tcpdump-link.map | sort -u > /out/linked-archives.raw

: > /out/linked-archives.txt
: > /out/matched-inventory.txt
inventory_errors=0
while IFS= read -r linked_archive; do
    case "${linked_archive}" in
        /*) archive_path="${linked_archive}" ;;
        *) archive_path="${tcpdump_build}/${linked_archive}" ;;
    esac
    archive_path="$(readlink -f "${archive_path}")"

    case "${archive_path}" in
        "${tcpdump_build}/libnetdissect.a") inventory_key=libnetdissect.a ;;
        "${prefix}/lib/libpcap.a") inventory_key=libpcap.a ;;
        *) inventory_key="${archive_path}" ;;
    esac

    inventory_row="$(awk -F '\t' -v key="${inventory_key}" \
        '$1 == key { print; found = 1 } END { if (!found) exit 1 }' \
        "${archive_inventory}")" || {
            echo "error: linked archive is not inventoried: ${archive_path}" >&2
            inventory_errors=$((inventory_errors + 1))
            continue
        }
    printf '%s\n' "${inventory_row}" >> /out/linked-archives.txt
    printf '%s\n' "${inventory_key}" >> /out/matched-inventory.txt
done < /out/linked-archives.raw

tab="$(printf '\t')"
while IFS="${tab}" read -r inventory_key owner version license license_file source_evidence; do
    case "${inventory_key}" in "" | \#*) continue ;; esac

    if ! grep -Fxq "${inventory_key}" /out/matched-inventory.txt; then
        echo "error: inventoried archive was not present in the final link: ${inventory_key}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    if [ ! -r "${license_dir}/${license_file}" ]; then
        echo "error: missing license material for ${inventory_key}: ${license_file}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    case "${source_evidence}" in
        https://*) ;;
        *)
            echo "error: incomplete source evidence for ${inventory_key}" >&2
            inventory_errors=$((inventory_errors + 1))
            continue
            ;;
    esac

    case "${inventory_key}" in
        libnetdissect.a)
            if [ "${owner}" != tcpdump-source ] || [ "${version}" != "${SOURCE_VERSION}" ] || \
                [ "${license}" != "${SOURCE_LICENSE}" ] || [ "${source_evidence}" != "${SOURCE_UPSTREAM_URL}" ]; then
                echo "error: tcpdump source inventory does not match source.lock" >&2
                inventory_errors=$((inventory_errors + 1))
            fi
            ;;
        libpcap.a)
            if [ "${owner}" != libpcap-source ] || [ "${version}" != "${LIBPCAP_VERSION}" ] || \
                [ "${license}" != "${LIBPCAP_LICENSE}" ] || [ "${source_evidence}" != "${LIBPCAP_UPSTREAM_URL}" ]; then
                echo "error: libpcap source inventory does not match source.lock" >&2
                inventory_errors=$((inventory_errors + 1))
            fi
            ;;
        *)
            installed_owner="$(apk info -W "${inventory_key}" | sed 's/.* is owned by //')"
            if [ "${installed_owner}" != "${owner}-${version}" ]; then
                echo "error: ${inventory_key}: expected ${owner}-${version}, found ${installed_owner}" >&2
                inventory_errors=$((inventory_errors + 1))
                continue
            fi
            installed_license="$(sed -n "/^P:${owner}$/,/^$/s/^L://p" /lib/apk/db/installed)"
            if [ "${installed_license}" != "${license}" ]; then
                echo "error: ${owner}: expected license '${license}', found '${installed_license}'" >&2
                inventory_errors=$((inventory_errors + 1))
            fi
            ;;
    esac
done < "${archive_inventory}"

if [ "${inventory_errors}" -ne 0 ]; then
    echo "Linked archives observed in the final map:" >&2
    cat /out/linked-archives.raw >&2
    exit 1
fi

install -m 0755 tcpdump /out/tcpdump
strip /out/tcpdump
file /out/tcpdump

if ! readelf -h /out/tcpdump | grep -Eq 'Type:[[:space:]]+EXEC'; then
    echo "error: tcpdump is not an ELF ET_EXEC executable" >&2
    exit 1
fi
if ! readelf -h /out/tcpdump | grep -Eq 'Machine:[[:space:]]+Advanced Micro Devices X86-64'; then
    echo "error: tcpdump is not an x86-64 executable" >&2
    exit 1
fi
if readelf -l /out/tcpdump | grep -q 'Requesting program interpreter'; then
    echo "error: tcpdump has a dynamic program interpreter" >&2
    exit 1
fi
if readelf -d /out/tcpdump 2>/dev/null | grep -q '(NEEDED)'; then
    echo "error: tcpdump has dynamic library dependencies" >&2
    exit 1
fi
if readelf -S /out/tcpdump | grep -Eq '[.]debug|[.]symtab'; then
    echo "error: tcpdump retains debug or full symbol-table sections" >&2
    exit 1
fi

/usr/local/bin/smoke-test-tcpdump /out/tcpdump

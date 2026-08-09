#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

source_lock="/usr/local/share/static_bins/netstat/source.lock"
source_input_dir="/usr/local/share/static_bins/netstat/sources"
patch_input_dir="/usr/local/share/static_bins/netstat/patches"
patch_lock="${patch_input_dir}/patch.lock"
recipe_config="/usr/local/share/static_bins/netstat/netstat.config.make"
license_dir="/usr/local/share/licenses/netstat"
archive_inventory="${license_dir}/archive-inventory.tsv"
validator="/usr/local/bin/validate-netstat-elf"
target_cflags="-O2 -pipe"

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

source_dir="/build/net-tools-${SOURCE_VERSION}"
for command_name in awk cc cmp cp file grep make patch readelf readlink sed sha256sum sort strip tar; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done
if [ ! -r "${archive_inventory}" ] || [ ! -r "${recipe_config}" ]; then
    echo "error: missing netstat configuration or linked-archive inventory" >&2
    exit 1
fi

mkdir -p /build /out
source_archive="/build/${SOURCE_ARCHIVE}"
cp "${source_input_dir}/${SOURCE_ARCHIVE}" "${source_archive}"
printf '%s  %s\n' "${SOURCE_SHA256}" "${source_archive}" | sha256sum -c -
tar -xf "${source_archive}" -C /build

source_patch="${patch_input_dir}/${PATCH_1}"
printf '%s  %s\n' "${PATCH_1_SHA256}" "${source_patch}" | sha256sum -c -
cd "${source_dir}"
patch --fuzz=0 -p1 < "${source_patch}"

cp "${recipe_config}" config.make
if grep -Ev '^(# Complete noninteractive netstat feature configuration[.]|[A-Za-z0-9_]+=[01])$' \
    config.make | grep -q . ||
    [ "$(grep -Ec '^[A-Za-z0-9_]+=[01]$' config.make)" -ne 44 ] ||
    [ "$(cut -d= -f1 config.make | grep -v '^#' | sort | uniq -d | wc -l)" -ne 0 ]; then
    echo "error: malformed or duplicate netstat configuration" >&2
    exit 1
fi
for setting in I18N HAVE_AFIPX HAVE_AFATALK HAVE_AFAX25 HAVE_AFNETROM \
    HAVE_AFROSE HAVE_AFX25 HAVE_AFECONET HAVE_AFDECnet HAVE_AFASH \
    HAVE_AFBLUETOOTH HAVE_HWARC HAVE_HWSLIP HAVE_HWPPP HAVE_HWTUNNEL \
    HAVE_HWSTRIP HAVE_HWTR HAVE_HWAX25 HAVE_HWROSE HAVE_HWNETROM \
    HAVE_HWX25 HAVE_HWFR HAVE_HWSIT HAVE_HWFDDI HAVE_HWHIPPI HAVE_HWASH \
    HAVE_HWHDLCLAPB HAVE_HWIRDA HAVE_HWEC HAVE_HWEUI64 HAVE_HWIB \
    HAVE_FW_MASQUERADE HAVE_ARP_TOOLS HAVE_HOSTNAME_TOOLS \
    HAVE_HOSTNAME_SYMLINKS HAVE_IP_TOOLS HAVE_MII HAVE_PLIP_TOOLS \
    HAVE_SERIAL_TOOLS HAVE_SELINUX; do
    grep -Fxq "${setting}=0" config.make || {
        echo "error: expected disabled netstat setting: ${setting}" >&2
        exit 1
    }
done
for setting in HAVE_AFUNIX HAVE_AFINET HAVE_AFINET6 HAVE_HWETHER; do
    grep -Fxq "${setting}=1" config.make || {
        echo "error: expected enabled netstat setting: ${setting}" >&2
        exit 1
    }
done
awk -F= '/^[A-Za-z0-9_]+=[01]$/ { print "#define " $1 " " $2 }' \
    config.make > config.h
if [ "$(grep -c '^#define ' config.h)" -ne 44 ]; then
    echo "error: generated config.h is incomplete" >&2
    exit 1
fi

make version.h
if ! CFLAGS="${target_cflags}" \
    LDFLAGS="-static -Wl,-Map,/out/netstat-link.map" \
    make -j"${BUILD_JOBS}" V=1 netstat \
    > /out/netstat-build.log 2>&1; then
    tail -n 200 /out/netstat-build.log >&2
    exit 1
fi
tail -n 12 /out/netstat-build.log
for unwanted in ifconfig route nameif arp rarp hostname iptunnel ipmaddr \
    mii-tool plipconfig slattach; do
    if [ -e "${unwanted}" ]; then
        echo "error: netstat-only build unexpectedly produced ${unwanted}" >&2
        exit 1
    fi
done

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
' /out/netstat-link.map | sort -u > /out/linked-archives.raw

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
            if [ "${archive_path}" != "${source_dir}/lib/libnet-tools.a" ] ||
                [ "${package}" != net-tools ] || [ "${version}" != "${SOURCE_VERSION}" ]; then
                echo "error: wrong net-tools source inventory identity: ${archive_path}" >&2
                inventory_errors=$((inventory_errors + 1))
            fi
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

install -m 0755 netstat /out/netstat
strip /out/netstat
"${validator}" /out/netstat

version_output="$(/out/netstat --version)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | sed -n '1p')" != \
    "net-tools ${SOURCE_VERSION}" ]; then
    echo "error: unexpected netstat version" >&2
    exit 1
fi

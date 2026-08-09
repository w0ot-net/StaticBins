#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

recipe_dir=/usr/local/share/static_bins/curl
source_lock="${recipe_dir}/source.lock"
target_lock="${recipe_dir}/target.lock"
source_input_dir="${recipe_dir}/sources"
license_dir=/usr/local/share/licenses/curl
archive_inventory="${license_dir}/archive-inventory.tsv"
validator="${recipe_dir}/validate-elf.sh"

. "${source_lock}"
. "${target_lock}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256}"
: "${TARGET_CFLAGS:=}"

target_cflags="-O2 -pipe ${TARGET_CFLAGS}"
source_dir="/build/curl-${SOURCE_VERSION}"
for command_name in awk cc cp file grep make readelf readlink sed sha256sum sort strip tar; do
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
# config.guess otherwise mistakes QEMU-hosted 32-bit x86 for the x32 ABI.
if [ "${TARGET_ARCHITECTURE}" = x86 ]; then
    set -- --build=i586-alpine-linux-musl
else
    set --
fi

if ! CFLAGS="${target_cflags}" LDFLAGS="-static" \
    LIBS='-lpthread' ./configure "$@" \
        --disable-shared \
        --enable-static \
        --disable-dependency-tracking \
        --disable-manual \
        --disable-ftp \
        --disable-ldap \
        --disable-ldaps \
        --disable-rtsp \
        --disable-dict \
        --disable-telnet \
        --disable-tftp \
        --disable-pop3 \
        --disable-imap \
        --disable-smb \
        --disable-smtp \
        --disable-gopher \
        --disable-mqtt \
        --disable-ipfs \
        --disable-websockets \
        --disable-ntlm \
        --enable-file \
        --enable-http \
        --enable-proxy \
        --enable-ipv6 \
        --enable-unix-sockets \
        --enable-cookies \
        --enable-threaded-resolver \
        --with-openssl \
        --with-zlib \
        --without-brotli \
        --without-zstd \
        --without-libpsl \
        --without-libssh2 \
        --without-libssh \
        --without-libidn2 \
        --without-nghttp2 \
        --without-nghttp3 \
        --without-ngtcp2 \
        --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
        --without-ca-path \
        --without-ca-fallback \
        > /tmp/curl-configure.log 2>&1; then
    tail -n 200 /tmp/curl-configure.log >&2
    exit 1
fi
tail -n 45 /tmp/curl-configure.log

if ! make -j"${BUILD_JOBS}" -C lib V=1 > /tmp/curl-build.log 2>&1 ||
    ! make -C src V=1 curl \
        LDFLAGS='-all-static -Wl,-Map,/tmp/curl-link.map' \
        >> /tmp/curl-build.log 2>&1; then
    tail -n 200 /tmp/curl-build.log >&2
    exit 1
fi
tail -n 25 /tmp/curl-build.log
if [ "${TARGET_ARCHITECTURE}" = x86 ] &&
    ! grep -Fq -- '-march=i686 -msse2 -mfpmath=sse' /tmp/curl-build.log; then
    echo "error: x86 build log lacks the required i686/SSE2 baseline" >&2
    exit 1
fi

candidate=src/curl
if [ ! -x "${candidate}" ]; then
    echo "error: curl build did not produce ${candidate}" >&2
    exit 1
fi

awk '
    $1 == "LOAD" && $2 ~ /[.]a$/ { print $2 }
    {
        line = $0
        while (match(line, /[^[:space:]()]+[.]a[(]/)) {
            print substr(line, RSTART, RLENGTH - 1)
            line = substr(line, RSTART + RLENGTH)
        }
    }
' /tmp/curl-link.map | sort -u > /tmp/linked-archives.raw

tab="$(printf '\t')"
: > /tmp/matched-inventory.txt
inventory_errors=0
while IFS= read -r linked_archive; do
    case "${linked_archive}" in
        /*) archive_path="${linked_archive}" ;;
        *) archive_path="${source_dir}/src/${linked_archive}" ;;
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
    if [ -z "${package}" ] || [ -z "${version}" ] || [ -z "${license}" ] ||
        [ ! -r "${license_dir}/${license_file}" ] || [ -z "${source_evidence}" ]; then
        echo "error: incomplete linked-input evidence for ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    if [ "${origin}" = builder ]; then
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
    elif [ "${origin}" != source ] || [ "${version}" != "${SOURCE_VERSION}" ]; then
        echo "error: invalid source archive evidence for ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
    fi
done < "${archive_inventory}"

if [ "${inventory_errors}" -ne 0 ]; then
    echo "Linked archives observed in the curl map:" >&2
    cat /tmp/linked-archives.raw >&2
    exit 1
fi

install -m 0755 "${candidate}" /out/curl
strip /out/curl
"${validator}" /out/curl

version_output="$(/out/curl --version)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | sed -n '1p' | awk '{print $2}')" != \
    "${SOURCE_VERSION}" ]; then
    echo "error: unexpected curl version" >&2
    exit 1
fi
if [ "$(printf '%s\n' "${version_output}" | sed -n 's/^Protocols: //p')" != \
    'file http https' ]; then
    echo "error: curl protocol surface drifted" >&2
    exit 1
fi

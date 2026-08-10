#!/bin/sh

set -eu

: "${BUILD_JOBS:=8}"

recipe_dir=/usr/local/share/static_bins/bpftrace
source_lock="${recipe_dir}/source.lock"
target_lock="${recipe_dir}/target.lock"
source_input_dir="${recipe_dir}/sources"
source_patch="${recipe_dir}/patches/0001-alpine-static-link-compatibility.patch"
license_dir=/usr/local/share/licenses/bpftrace
archive_inventory="${license_dir}/archive-inventory.tsv"
header_inventory="${license_dir}/header-inputs.tsv"
packed_inventory="${license_dir}/packed-inputs.tsv"

for required_input in \
    "${source_lock}" "${target_lock}" "${source_patch}" \
    "${archive_inventory}" "${header_inventory}" "${packed_inventory}"; do
    if [ ! -r "${required_input}" ]; then
        echo "error: missing recipe input: ${required_input}" >&2
        exit 1
    fi
done

# shellcheck source=source.lock
. "${source_lock}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"
: "${SOURCE_ARCHIVE:?missing SOURCE_ARCHIVE in source.lock}"
: "${SOURCE_SHA256:?missing SOURCE_SHA256 in source.lock}"
: "${SOURCE_UPSTREAM_URL:?missing SOURCE_UPSTREAM_URL in source.lock}"
: "${SOURCE_LICENSE:?missing SOURCE_LICENSE in source.lock}"
: "${SOURCE_AUTHENTICATION:?missing SOURCE_AUTHENTICATION in source.lock}"

# shellcheck source=target.lock
. "${target_lock}"
: "${EXPECTED_MACHINE:?missing EXPECTED_MACHINE in target.lock}"
: "${EXPECTED_CLASS:?missing EXPECTED_CLASS in target.lock}"
: "${EXPECTED_DATA:?missing EXPECTED_DATA in target.lock}"

case "${SOURCE_ARCHIVE}" in
    */* | "")
        echo "error: SOURCE_ARCHIVE must be a filename" >&2
        exit 1
        ;;
esac
if [ "${SOURCE_AUTHENTICATION}" != checksum-only ]; then
    echo "error: unsupported bpftrace source authentication mode" >&2
    exit 1
fi

for command_name in \
    apk awk cmake cp file grep ninja patch readelf readlink sed sha256sum \
    sort strip tar upx; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done

source_dir="/build/bpftrace-${SOURCE_VERSION}"
build_dir="${source_dir}/build"
mkdir -p /build /out
cd /build

source_input="${source_input_dir}/${SOURCE_ARCHIVE}"
source_archive="/build/${SOURCE_ARCHIVE}"
if [ ! -f "${source_input}" ]; then
    echo "error: missing tracked bpftrace source archive: ${source_input}" >&2
    exit 1
fi
cp "${source_input}" "${source_archive}"
echo "${SOURCE_SHA256}  ${source_archive}" | sha256sum -c -

tar -xf "${source_archive}"
cd "${source_dir}"
patch -p1 < "${source_patch}"

if ! cmake -S . -B "${build_dir}" -G Ninja \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DBUILD_TESTING=OFF \
    -DENABLE_MAN=OFF \
    -DENABLE_SKB_OUTPUT=OFF \
    -DSTATIC_LINKING=ON \
    -DUSE_SYSTEM_LIBBPF=ON \
    -DCMAKE_PREFIX_PATH=/usr/lib/llvm20/lib/cmake \
    -DLLVM_REQUESTED_VERSION=20.1.8 \
    -DCMAKE_EXE_LINKER_FLAGS=-Wl,-Map,/out/bpftrace-link.map \
    > /out/bpftrace-configure.log 2>&1; then
    cat /out/bpftrace-configure.log >&2
    exit 1
fi
tail -n 8 /out/bpftrace-configure.log

if ! cmake --build "${build_dir}" --target bpftrace --parallel "${BUILD_JOBS}" \
    > /out/bpftrace-build.log 2>&1; then
    cat /out/bpftrace-build.log >&2
    exit 1
fi
tail -n 8 /out/bpftrace-build.log

# GNU ld's map is the evidence for the exact external archives selected by the
# final link. Both member-reference and LOAD records are needed because archive
# groups may appear in only one form.
{
    grep -aoE '[^[:space:]()]+[.]a[(]' /out/bpftrace-link.map | sed 's/($//'
    grep -aE '^LOAD [^[:space:]]+[.]a$' /out/bpftrace-link.map | awk '{ print $2 }'
} | sort -u > /out/linked-archives.raw

if [ ! -s /out/linked-archives.raw ]; then
    echo "error: final link map contained no static archives" >&2
    exit 1
fi

: > /out/linked-archives.txt
: > /out/matched-inventory.txt
internal_archive_count=0
inventory_errors=0
tab="$(printf '\t')"

while IFS= read -r linked_archive; do
    case "${linked_archive}" in
        /*)
            archive_candidate="${linked_archive}"
            ;;
        *)
            archive_candidate="${build_dir}/${linked_archive}"
            if [ ! -e "${archive_candidate}" ]; then
                archive_candidate="${source_dir}/${linked_archive}"
            fi
            ;;
    esac
    if [ ! -e "${archive_candidate}" ]; then
        echo "error: linked archive path cannot be resolved: ${linked_archive}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    archive_path="$(readlink -f "${archive_candidate}")"

    case "${archive_path}" in
        "${build_dir}"/* | "${source_dir}"/*)
            printf 'bpftrace-source\t%s\t%s\t%s\n' \
                "${SOURCE_VERSION}" "${SOURCE_LICENSE}" "${archive_path}" \
                >> /out/linked-archives.txt
            internal_archive_count=$((internal_archive_count + 1))
            continue
            ;;
    esac

    match_count=0
    matched_pattern=""
    matched_package=""
    matched_version=""
    matched_license=""
    matched_license_file=""
    matched_source=""
    while IFS="${tab}" read -r \
        archive_pattern package version license license_file aports_source; do
        case "${archive_pattern}" in "" | \#*) continue ;; esac
        case "${archive_path}" in
            ${archive_pattern})
                match_count=$((match_count + 1))
                matched_pattern="${archive_pattern}"
                matched_package="${package}"
                matched_version="${version}"
                matched_license="${license}"
                matched_license_file="${license_file}"
                matched_source="${aports_source}"
                ;;
        esac
    done < "${archive_inventory}"

    if [ "${match_count}" -ne 1 ]; then
        echo "error: linked archive matched ${match_count} inventory rows: ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    if [ ! -r "${license_dir}/${matched_license_file}" ]; then
        echo "error: missing license material for ${archive_path}: ${matched_license_file}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    if [ -z "${matched_license}" ] || [ -z "${matched_source}" ]; then
        echo "error: incomplete inventory row for ${archive_path}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    installed_owner="$(apk info -W "${archive_path}" | sed 's/.* is owned by //')"
    if [ "${installed_owner}" != "${matched_package}-${matched_version}" ]; then
        echo "error: ${archive_path}: expected ${matched_package}-${matched_version}, found ${installed_owner}" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    installed_license="$(sed -n "/^P:${matched_package}$/,/^$/s/^L://p" /lib/apk/db/installed)"
    if [ "${installed_license}" != "${matched_license}" ]; then
        echo "error: ${matched_package}: expected license '${matched_license}', found '${installed_license}'" >&2
        inventory_errors=$((inventory_errors + 1))
        continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${archive_path}" "${matched_package}" "${matched_version}" \
        "${matched_license}" "${matched_license_file}" "${matched_source}" \
        "${matched_pattern}" >> /out/linked-archives.txt
    printf '%s\n' "${matched_pattern}" >> /out/matched-inventory.txt
done < /out/linked-archives.raw

if [ "${internal_archive_count}" -eq 0 ]; then
    echo "error: final link map contained no bpftrace-source archive" >&2
    inventory_errors=$((inventory_errors + 1))
fi

while IFS="${tab}" read -r archive_pattern _rest; do
    case "${archive_pattern}" in "" | \#*) continue ;; esac
    if ! grep -Fxq "${archive_pattern}" /out/matched-inventory.txt; then
        echo "error: inventoried archive pattern was absent from the final link: ${archive_pattern}" >&2
        inventory_errors=$((inventory_errors + 1))
    fi
done < "${archive_inventory}"

validate_nonarchive_input() {
    inventory_file="$1"
    input_kind="$2"
    while IFS="${tab}" read -r \
        input_path package version license license_file aports_source; do
        case "${input_path}" in "" | \#*) continue ;; esac
        if [ ! -r "${input_path}" ]; then
            echo "error: missing ${input_kind} input: ${input_path}" >&2
            inventory_errors=$((inventory_errors + 1))
            continue
        fi
        if [ ! -r "${license_dir}/${license_file}" ]; then
            echo "error: missing license material for ${input_path}: ${license_file}" >&2
            inventory_errors=$((inventory_errors + 1))
            continue
        fi
        if [ -z "${license}" ] || [ -z "${aports_source}" ]; then
            echo "error: incomplete ${input_kind} inventory row for ${input_path}" >&2
            inventory_errors=$((inventory_errors + 1))
            continue
        fi
        installed_owner="$(apk info -W "${input_path}" | sed 's/.* is owned by //')"
        if [ "${installed_owner}" != "${package}-${version}" ]; then
            echo "error: ${input_path}: expected ${package}-${version}, found ${installed_owner}" >&2
            inventory_errors=$((inventory_errors + 1))
            continue
        fi
        installed_license="$(sed -n "/^P:${package}$/,/^$/s/^L://p" /lib/apk/db/installed)"
        if [ "${installed_license}" != "${license}" ]; then
            echo "error: ${package}: expected license '${license}', found '${installed_license}'" >&2
            inventory_errors=$((inventory_errors + 1))
        fi
    done < "${inventory_file}"
}

validate_nonarchive_input "${header_inventory}" header
validate_nonarchive_input "${packed_inventory}" packer

if [ "${inventory_errors}" -ne 0 ]; then
    echo "Linked archives observed in the final map:" >&2
    cat /out/linked-archives.raw >&2
    exit 1
fi

install -m 0755 "${build_dir}/src/bpftrace" /out/bpftrace.unpacked
strip /out/bpftrace.unpacked
/usr/local/bin/validate-static-bpftrace \
    /out/bpftrace.unpacked "${EXPECTED_MACHINE}" "${EXPECTED_CLASS}" "${EXPECTED_DATA}"

version_output="$(/out/bpftrace.unpacked --version 2>&1)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | sed -n '1p')" != \
    "bpftrace v${SOURCE_VERSION}" ]; then
    echo "error: unexpected unpacked bpftrace version" >&2
    exit 1
fi

cp /out/bpftrace.unpacked /out/bpftrace
# Maximum LZMA compression is disproportionately slow under QEMU. UPX level 6
# keeps the AArch64 artifact below the repository hosting limit while retaining
# a practical emulated rebuild time.
upx -6 /out/bpftrace
upx -t /out/bpftrace
/usr/local/bin/validate-static-bpftrace \
    /out/bpftrace "${EXPECTED_MACHINE}" "${EXPECTED_CLASS}" "${EXPECTED_DATA}"

packed_version_output="$(/out/bpftrace --version 2>&1)"
printf '%s\n' "${packed_version_output}"
if [ "$(printf '%s\n' "${packed_version_output}" | sed -n '1p')" != \
    "bpftrace v${SOURCE_VERSION}" ]; then
    echo "error: unexpected packed bpftrace version" >&2
    exit 1
fi

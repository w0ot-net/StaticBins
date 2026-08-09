#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 READELF FIXTURE EXPECTED_VERSION" >&2
    exit 2
fi

readelf_binary="$1"
fixture_binary="$2"
expected_version="$3"
temporary_dir="$(mktemp -d)"

cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_line="$(${readelf_binary} --version | sed -n '1p')"
if [ "${version_line}" != "GNU readelf (GNU Binutils) ${expected_version}" ]; then
    echo "error: unexpected readelf version: ${version_line}" >&2
    exit 1
fi

timeout 30 "${readelf_binary}" -hW "${fixture_binary}" \
    > "${temporary_dir}/file-header.txt"
timeout 30 "${readelf_binary}" -lW "${fixture_binary}" \
    > "${temporary_dir}/program-headers.txt"
timeout 30 "${readelf_binary}" -SW "${fixture_binary}" \
    > "${temporary_dir}/sections.txt"
timeout 30 "${readelf_binary}" -sW "${fixture_binary}" \
    > "${temporary_dir}/symbols.txt"
timeout 30 "${readelf_binary}" --debug-dump=info "${fixture_binary}" \
    > "${temporary_dir}/debug-info.txt"

grep -Fq 'ELF Header:' "${temporary_dir}/file-header.txt"
grep -Eq 'Type:[[:space:]]+EXEC' "${temporary_dir}/file-header.txt"
grep -Eq '[[:space:]]LOAD[[:space:]]' "${temporary_dir}/program-headers.txt"
grep -Eq '[[:space:]][.]text[[:space:]]' "${temporary_dir}/sections.txt"
grep -Eq '[[:space:]][.]debug_info[[:space:]]' "${temporary_dir}/sections.txt"
grep -Eq '[[:space:]]static_bins_probe$' "${temporary_dir}/symbols.txt"
grep -Eq '[[:space:]]static_bins_data$' "${temporary_dir}/symbols.txt"
grep -Eq 'DW_AT_name.*static_bins_probe' "${temporary_dir}/debug-info.txt"

echo "validated readelf ELF headers, sections, symbols, and DWARF information"

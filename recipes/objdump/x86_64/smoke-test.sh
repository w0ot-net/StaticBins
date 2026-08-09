#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 OBJDUMP FIXTURE_OBJECT EXPECTED_VERSION" >&2
    exit 2
fi

objdump_binary="$1"
fixture_object="$2"
expected_version="$3"
temporary_dir="$(mktemp -d)"

cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_line="$(${objdump_binary} --version | sed -n '1p')"
if [ "${version_line}" != "GNU objdump (GNU Binutils) ${expected_version}" ]; then
    echo "error: unexpected objdump version: ${version_line}" >&2
    exit 1
fi

timeout 30 "${objdump_binary}" -f "${fixture_object}" \
    > "${temporary_dir}/file-header.txt"
timeout 30 "${objdump_binary}" -h "${fixture_object}" \
    > "${temporary_dir}/sections.txt"
timeout 30 "${objdump_binary}" -t "${fixture_object}" \
    > "${temporary_dir}/symbols.txt"
timeout 30 "${objdump_binary}" -d "${fixture_object}" \
    > "${temporary_dir}/disassembly.txt"

grep -Fq 'file format elf' "${temporary_dir}/file-header.txt"
grep -Eq '[[:space:]][.]text[[:space:]]' "${temporary_dir}/sections.txt"
grep -Eq '[[:space:]]static_bins_probe$' "${temporary_dir}/symbols.txt"
grep -Eq '[[:space:]]static_bins_data$' "${temporary_dir}/symbols.txt"
grep -Fq '<static_bins_probe>:' "${temporary_dir}/disassembly.txt"

echo "validated objdump target object headers, sections, symbols, and disassembly"

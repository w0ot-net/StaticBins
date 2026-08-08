#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: validate-elf.sh <binary>" >&2
    exit 2
fi

binary="$1"

if [ ! -f "${binary}" ] || [ ! -x "${binary}" ]; then
    echo "error: AArch64 GDB candidate is not a regular executable: ${binary}" >&2
    exit 1
fi

for command_name in file grep readelf; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: required command not found: ${command_name}" >&2
        exit 1
    fi
done

elf_header="$(readelf -W -h "${binary}")"
program_headers="$(readelf -W -l "${binary}")"
dynamic_tags="$(readelf -W -d "${binary}")"
section_headers="$(readelf -W -S "${binary}")"

file "${binary}"

if ! printf '%s\n' "${elf_header}" | grep -Eq 'Class:[[:space:]]+ELF64'; then
    echo "error: AArch64 GDB is not ELF64" >&2
    exit 1
fi
if ! printf '%s\n' "${elf_header}" | grep -Eq "Data:[[:space:]]+2.s complement, little endian"; then
    echo "error: AArch64 GDB is not little-endian" >&2
    exit 1
fi
if ! printf '%s\n' "${elf_header}" | grep -Eq 'Machine:[[:space:]]+AArch64'; then
    echo "error: GDB is not an AArch64 executable" >&2
    exit 1
fi
if ! printf '%s\n' "${elf_header}" | grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)'; then
    echo "error: AArch64 GDB is not an ELF ET_DYN static-PIE executable" >&2
    exit 1
fi
if ! printf '%s\n' "${elf_header}" | grep -Eq 'Entry point address:[[:space:]]+0x0*[1-9a-fA-F][0-9a-fA-F]*[[:space:]]*$'; then
    echo "error: AArch64 GDB static PIE has no executable entry point" >&2
    exit 1
fi
if ! printf '%s\n' "${program_headers}" | grep -Eq '^[[:space:]]*LOAD[[:space:]].*[[:space:]]E([[:space:]]|$)'; then
    echo "error: AArch64 GDB static PIE has no executable PT_LOAD segment" >&2
    exit 1
fi
if printf '%s\n' "${program_headers}" | grep -Eq '^[[:space:]]*INTERP[[:space:]]'; then
    echo "error: AArch64 GDB has a dynamic program interpreter" >&2
    exit 1
fi
if ! printf '%s\n' "${dynamic_tags}" | grep -Eq '\(FLAGS_1\).*PIE([[:space:]]|$)'; then
    echo "error: AArch64 GDB ET_DYN output does not carry DF_1_PIE" >&2
    exit 1
fi
if printf '%s\n' "${dynamic_tags}" | grep -q '(NEEDED)'; then
    echo "error: AArch64 GDB has dynamic library dependencies" >&2
    exit 1
fi
if printf '%s\n' "${dynamic_tags}" | grep -q 'TEXTREL'; then
    echo "error: AArch64 GDB static PIE requires text relocations" >&2
    exit 1
fi
if printf '%s\n' "${section_headers}" | grep -Eq '[.]debug|[.]symtab'; then
    echo "error: AArch64 GDB retains debug or full symbol-table sections" >&2
    exit 1
fi

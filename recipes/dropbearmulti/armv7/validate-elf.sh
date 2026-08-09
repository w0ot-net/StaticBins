#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 BINARY" >&2
    exit 2
fi

binary="$1"
elf_header="$(readelf -hW "${binary}")"
program_headers="$(readelf -lW "${binary}")"
dynamic_tags="$(readelf -dW "${binary}")"
section_headers="$(readelf -SW "${binary}")"

file "${binary}"
if ! file "${binary}" | grep -q 'static-pie linked'; then
    echo "error: dropbearmulti is not reported as static PIE" >&2
    exit 1
fi
if ! printf '%s\n' "${elf_header}" | grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' ||
    ! printf '%s\n' "${elf_header}" | grep -Eq 'Machine:[[:space:]]+ARM' ||
    ! printf '%s\n' "${elf_header}" | grep -Eq 'Class:[[:space:]]+ELF32' ||
    ! printf '%s\n' "${elf_header}" | grep -Eq 'Data:[[:space:]]+2.s complement, little endian' ||
    ! printf '%s\n' "${elf_header}" | grep -Eq 'Flags:.*Version5 EABI.*hard-float ABI'; then
    echo "error: dropbearmulti is not ARMv7 ELF32 little-endian EABI5 hard-float static PIE" >&2
    exit 1
fi
if ! printf '%s\n' "${elf_header}" | grep -Eq \
    'Entry point address:[[:space:]]+0x0*[1-9a-fA-F][0-9a-fA-F]*[[:space:]]*$' ||
    ! printf '%s\n' "${program_headers}" | grep -Eq \
    '^[[:space:]]*LOAD[[:space:]].*[[:space:]]E([[:space:]]|$)'; then
    echo "error: dropbearmulti static PIE lacks an executable entry point or PT_LOAD" >&2
    exit 1
fi
if printf '%s\n' "${program_headers}" | grep -Eq '^[[:space:]]*INTERP[[:space:]]' ||
    printf '%s\n' "${dynamic_tags}" | grep -q '(NEEDED)'; then
    echo "error: dropbearmulti has a dynamic interpreter or shared dependency" >&2
    exit 1
fi
if ! printf '%s\n' "${dynamic_tags}" | grep -Eq '\(FLAGS_1\).*PIE([[:space:]]|$)' ||
    printf '%s\n' "${dynamic_tags}" | grep -Eq '\(TEXTREL\)|FLAGS.*TEXTREL'; then
    echo "error: dropbearmulti does not satisfy the static-PIE dynamic-tag contract" >&2
    exit 1
fi
if printf '%s\n' "${section_headers}" | grep -Eq '[.]debug|[.]symtab'; then
    echo "error: dropbearmulti retains debug or full symbol-table sections" >&2
    exit 1
fi

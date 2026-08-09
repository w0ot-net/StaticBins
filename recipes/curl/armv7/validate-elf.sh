#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 BINARY" >&2
    exit 2
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${script_dir}/target.lock"
binary="$1"
elf_header="$(readelf -hW "${binary}")"
program_headers="$(readelf -lW "${binary}")"
dynamic_tags="$(readelf -dW "${binary}")"
section_headers="$(readelf -SW "${binary}")"

file "${binary}"
if ! file "${binary}" | grep -q 'static-pie linked'; then
    echo "error: curl is not reported as static PIE" >&2
    exit 1
fi
if ! printf '%s\n' "${elf_header}" | grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' ||
    ! printf '%s\n' "${elf_header}" | grep -Fq "Machine:                           ${EXPECTED_MACHINE}" ||
    ! printf '%s\n' "${elf_header}" | grep -Eq "Class:[[:space:]]+${EXPECTED_CLASS}" ||
    ! printf '%s\n' "${elf_header}" | grep -Eq 'Data:[[:space:]]+2.s complement, little endian'; then
    echo "error: curl does not match the ${TARGET_DISPLAY} ELF contract" >&2
    exit 1
fi
if [ "${TARGET_ARCHITECTURE}" = armv7 ] &&
    { ! printf '%s\n' "${elf_header}" | grep -Eq 'Flags:.*Version5 EABI' ||
      ! printf '%s\n' "${elf_header}" | grep -Eq 'Flags:.*hard-float ABI'; }; then
    echo "error: curl is not ARM EABI5 hard-float" >&2
    exit 1
fi
if ! printf '%s\n' "${elf_header}" | grep -Eq \
    'Entry point address:[[:space:]]+0x0*[1-9a-fA-F][0-9a-fA-F]*[[:space:]]*$' ||
    ! printf '%s\n' "${program_headers}" | grep -Eq \
    '^[[:space:]]*LOAD[[:space:]].*[[:space:]]E([[:space:]]|$)'; then
    echo "error: curl static PIE lacks an executable entry point or PT_LOAD" >&2
    exit 1
fi
if printf '%s\n' "${program_headers}" | grep -Eq '^[[:space:]]*INTERP[[:space:]]' ||
    printf '%s\n' "${dynamic_tags}" | grep -q '(NEEDED)'; then
    echo "error: curl has a dynamic interpreter or shared dependency" >&2
    exit 1
fi
if ! printf '%s\n' "${dynamic_tags}" | grep -Eq '\(FLAGS_1\).*PIE([[:space:]]|$)' ||
    printf '%s\n' "${dynamic_tags}" | grep -Eq '\(TEXTREL\)|FLAGS.*TEXTREL'; then
    echo "error: curl does not satisfy the static-PIE dynamic-tag contract" >&2
    exit 1
fi
if printf '%s\n' "${section_headers}" | grep -Eq '[.]debug|[.]symtab'; then
    echo "error: curl retains debug or full symbol-table sections" >&2
    exit 1
fi

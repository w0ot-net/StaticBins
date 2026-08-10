#!/bin/sh

set -eu

if [ "$#" -ne 4 ]; then
    echo "usage: $0 BINARY EXPECTED_MACHINE EXPECTED_CLASS EXPECTED_DATA" >&2
    exit 1
fi

binary="$1"
expected_machine="$2"
expected_class="$3"
expected_data="$4"

for command_name in file grep readelf; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: ${command_name} is required to validate bpftrace" >&2
        exit 1
    fi
done

file "${binary}"
if ! file "${binary}" | grep -q 'statically linked'; then
    echo "error: bpftrace is not reported as statically linked" >&2
    exit 1
fi
if ! readelf -hW "${binary}" | grep -Eq 'Type:[[:space:]]+EXEC'; then
    echo "error: bpftrace is not a classic static ET_EXEC executable" >&2
    exit 1
fi
if ! readelf -hW "${binary}" | grep -Fq "Class:                             ${expected_class}"; then
    echo "error: bpftrace has the wrong ELF class" >&2
    exit 1
fi
if ! readelf -hW "${binary}" | grep -Fq "Data:                              ${expected_data}"; then
    echo "error: bpftrace has the wrong ELF byte order" >&2
    exit 1
fi
if ! readelf -hW "${binary}" | grep -Eq "Machine:[[:space:]]+${expected_machine}"; then
    echo "error: bpftrace has the wrong ELF machine" >&2
    exit 1
fi
if ! readelf -hW "${binary}" | grep -Eq 'OS/ABI:[[:space:]]+UNIX - System V'; then
    echo "error: bpftrace has the wrong ELF ABI" >&2
    exit 1
fi
if ! readelf -hW "${binary}" | grep -Eq 'ABI Version:[[:space:]]+0'; then
    echo "error: bpftrace has the wrong ELF ABI version" >&2
    exit 1
fi
if ! readelf -hW "${binary}" | grep -Eq \
    'Entry point address:[[:space:]]+0x[1-9a-fA-F][0-9a-fA-F]*'; then
    echo "error: bpftrace has no executable entry point" >&2
    exit 1
fi
if ! readelf -lW "${binary}" | grep -Eq 'LOAD.*R E'; then
    echo "error: bpftrace has no executable PT_LOAD segment" >&2
    exit 1
fi
if readelf -lW "${binary}" | grep -q 'Requesting program interpreter'; then
    echo "error: bpftrace has a dynamic program interpreter" >&2
    exit 1
fi
if readelf -dW "${binary}" 2>/dev/null | grep -q '(NEEDED)'; then
    echo "error: bpftrace has dynamic library dependencies" >&2
    readelf -dW "${binary}" | grep '(NEEDED)' >&2
    exit 1
fi
if readelf -SW "${binary}" 2>/dev/null | grep -Eq '[.]debug|[.]symtab'; then
    echo "error: bpftrace retains debug or full symbol-table sections" >&2
    exit 1
fi

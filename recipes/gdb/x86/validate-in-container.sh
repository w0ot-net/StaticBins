#!/bin/sh

set -eu

source_lock="/usr/local/share/static_bins/gdb/source.lock"

# shellcheck source=source.lock
. "${source_lock}"
: "${SOURCE_VERSION:?missing SOURCE_VERSION in source.lock}"

for command_name in file readelf; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: locked builder is missing ${command_name}" >&2
        exit 1
    fi
done

if ! file /out/gdb | grep -Eq 'ELF 32-bit LSB executable, Intel (i386|80386)'; then
    echo "error: GDB is not a 32-bit little-endian x86 executable" >&2
    exit 1
fi
if ! readelf -h /out/gdb | grep -Eq 'Class:[[:space:]]+ELF32'; then
    echo "error: GDB is not ELF32" >&2
    exit 1
fi
if ! readelf -h /out/gdb | grep -Eq "Data:[[:space:]]+2's complement, little endian"; then
    echo "error: GDB is not little-endian" >&2
    exit 1
fi
if ! readelf -h /out/gdb | grep -Eq 'Machine:[[:space:]]+Intel 80386'; then
    echo "error: GDB is not an Intel 80386 executable" >&2
    readelf -h /out/gdb >&2
    exit 1
fi
if ! readelf -h /out/gdb | grep -Eq 'Type:[[:space:]]+EXEC'; then
    echo "error: GDB is not an ELF ET_EXEC executable" >&2
    exit 1
fi
if readelf -l /out/gdb | grep -q 'Requesting program interpreter'; then
    echo "error: GDB has a dynamic program interpreter" >&2
    exit 1
fi
if readelf -d /out/gdb 2>/dev/null | grep -q '(NEEDED)'; then
    echo "error: GDB has dynamic library dependencies" >&2
    readelf -d /out/gdb | grep '(NEEDED)' >&2
    exit 1
fi
if readelf -S /out/gdb | grep -Eq '[.]debug|[.]symtab'; then
    echo "error: GDB retains debug or full symbol-table sections" >&2
    exit 1
fi

version_output="$(/out/gdb --batch --nx --version 2>&1)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | sed -n '1p')" != \
    "GNU gdb (GDB) ${SOURCE_VERSION}" ]; then
    echo "error: unexpected GDB version" >&2
    exit 1
fi

#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 BINARY" >&2
    exit 2
fi

BINARY="$1"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TARGET_LOCK="${TARGET_LOCK:-${SCRIPT_DIR}/target.lock}"

# shellcheck source=target.lock
. "${TARGET_LOCK}"
: "${TARGET_ARCHITECTURE:?missing TARGET_ARCHITECTURE}"
: "${TARGET_CFLAGS:?missing TARGET_CFLAGS}"
: "${EXPECTED_MACHINE:?missing EXPECTED_MACHINE}"
: "${EXPECTED_CLASS:?missing EXPECTED_CLASS}"
: "${EXPECTED_DATA:?missing EXPECTED_DATA}"

for command_name in file readelf; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: ${command_name} is required" >&2
        exit 1
    fi
done
if [ ! -f "${BINARY}" ]; then
    echo "error: missing Binutils artifact candidate: ${BINARY}" >&2
    exit 1
fi

file "${BINARY}"
if ! file "${BINARY}" | grep -q 'static-pie linked'; then
    echo "error: output is not reported as static PIE" >&2
    exit 1
fi
if ! readelf -hW "${BINARY}" | grep -Eq \
    "Class:[[:space:]]+${EXPECTED_CLASS}" ||
    ! readelf -hW "${BINARY}" | grep -Eq \
    "Data:[[:space:]]+${EXPECTED_DATA}" ||
    ! readelf -hW "${BINARY}" | grep -Eq \
    'Type:[[:space:]]+DYN .*Position-Independent Executable' ||
    ! readelf -hW "${BINARY}" | grep -Eq \
    "Machine:[[:space:]]+${EXPECTED_MACHINE}"; then
    echo "error: output has the wrong ELF identity for ${TARGET_ARCHITECTURE}" >&2
    readelf -hW "${BINARY}" >&2
    exit 1
fi
if ! readelf -hW "${BINARY}" | grep -Eq \
    'Entry point address:[[:space:]]+0x[1-9a-fA-F][0-9a-fA-F]*'; then
    echo "error: static PIE has no executable entry point" >&2
    exit 1
fi
if ! readelf -lW "${BINARY}" | grep -Eq \
    'LOAD[[:space:]].*[[:space:]]R E[[:space:]]'; then
    echo "error: static PIE has no executable PT_LOAD segment" >&2
    exit 1
fi
if readelf -lW "${BINARY}" | grep -q 'Requesting program interpreter'; then
    echo "error: output has a dynamic program interpreter" >&2
    exit 1
fi
if readelf -dW "${BINARY}" 2>/dev/null | grep -q '(NEEDED)'; then
    echo "error: output has dynamic library dependencies" >&2
    exit 1
fi
if ! readelf -dW "${BINARY}" | grep -Eq '\(FLAGS_1\).*PIE'; then
    echo "error: ET_DYN output is not marked PIE" >&2
    exit 1
fi
if readelf -dW "${BINARY}" | grep -Eq '\(TEXTREL\)|\(FLAGS\).*TEXTREL'; then
    echo "error: static PIE contains text relocations" >&2
    exit 1
fi
if readelf -SW "${BINARY}" | grep -Eq '[.]debug|[.]symtab'; then
    echo "error: output retains debug or full symbol-table sections" >&2
    exit 1
fi

case "${TARGET_ARCHITECTURE}" in
    armv7)
        if ! readelf -hW "${BINARY}" | grep -Eq 'Flags:.*hard-float ABI'; then
            echo "error: ARMv7 output is not hard-float EABI" >&2
            exit 1
        fi
        ;;
    x86)
        for required_flag in -march=i686 -msse2 -mfpmath=sse; do
            case " ${TARGET_CFLAGS} " in
                *" ${required_flag} "*) ;;
                *)
                    echo "error: x86 build lock omits ${required_flag}" >&2
                    exit 1
                    ;;
            esac
        done
        ;;
esac

#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 GDB SMOKE_TARGET VERSION" >&2
    exit 1
fi

gdb="$1"
smoke_target="$2"
expected_version="$3"

version_output="$("${gdb}" --batch --nx --version 2>&1)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | sed -n '1p')" != \
    "GNU gdb (GDB) ${expected_version}" ]; then
    echo "error: unexpected GDB version" >&2
    exit 1
fi

inspection_output="$(LC_ALL=C "${gdb}" --batch --nx \
    -ex "file ${smoke_target}" \
    -ex 'show architecture' \
    -ex 'info address static_bins_probe_value' \
    -ex 'print/x static_bins_probe_value' 2>&1)"
printf '%s\n' "${inspection_output}"

if ! printf '%s\n' "${inspection_output}" | grep -Eq \
    'currently "arm[^"]*"'; then
    echo "error: GDB did not report an ARM target architecture" >&2
    exit 1
fi
if ! printf '%s\n' "${inspection_output}" | grep -Fq \
    'Symbol "static_bins_probe_value" is static storage at address'; then
    echo "error: GDB did not resolve the smoke target symbol" >&2
    exit 1
fi
if ! printf '%s\n' "${inspection_output}" | grep -Fqx '$1 = 0x12345678'; then
    echo "error: GDB did not evaluate the smoke target data" >&2
    exit 1
fi

echo "validated ARMv7 BFD loading, architecture, symbol, and data inspection"

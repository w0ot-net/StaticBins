#!/bin/sh

set -eu

if [ "$#" -ne 4 ]; then
    echo "usage: $0 NM FIXTURE_OBJECT FIXTURE_ARCHIVE EXPECTED_VERSION" >&2
    exit 2
fi

nm_binary="$1"
fixture_object="$2"
fixture_archive="$3"
expected_version="$4"
temporary_dir="$(mktemp -d)"

cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_line="$(${nm_binary} --version | sed -n '1p')"
if [ "${version_line}" != "GNU nm (GNU Binutils) ${expected_version}" ]; then
    echo "error: unexpected nm version: ${version_line}" >&2
    exit 1
fi

timeout 30 "${nm_binary}" -P "${fixture_object}" \
    > "${temporary_dir}/symbols.txt"
timeout 30 "${nm_binary}" --defined-only -P "${fixture_object}" \
    > "${temporary_dir}/defined.txt"
timeout 30 "${nm_binary}" --undefined-only -P "${fixture_object}" \
    > "${temporary_dir}/undefined.txt"
timeout 30 "${nm_binary}" -n -P "${fixture_object}" \
    > "${temporary_dir}/numeric.txt"
timeout 30 "${nm_binary}" -A -P "${fixture_archive}" \
    > "${temporary_dir}/archive.txt"

grep -Eq '^static_bins_data D ' "${temporary_dir}/symbols.txt"
grep -Eq '^static_bins_local t ' "${temporary_dir}/symbols.txt"
grep -Eq '^static_bins_missing U([[:space:]]|$)' "${temporary_dir}/symbols.txt"
grep -Eq '^static_bins_probe T ' "${temporary_dir}/symbols.txt"

grep -Eq '^static_bins_probe T ' "${temporary_dir}/defined.txt"
if grep -Eq '^static_bins_missing ' "${temporary_dir}/defined.txt"; then
    echo "error: --defined-only retained an undefined symbol" >&2
    exit 1
fi
grep -Eq '^static_bins_missing U([[:space:]]|$)' \
    "${temporary_dir}/undefined.txt"
if grep -Eq '^static_bins_probe ' "${temporary_dir}/undefined.txt"; then
    echo "error: --undefined-only retained a defined symbol" >&2
    exit 1
fi

awk '
    /^(main|static_bins_data|static_bins_local|static_bins_missing|static_bins_probe) / {
        names = names (names == "" ? "" : " ") $1
    }
    END {
        if (names != "main static_bins_data static_bins_local static_bins_missing static_bins_probe")
            exit 1
    }
' "${temporary_dir}/symbols.txt"

awk '
    function hex_value(text, index_value, result, digit) {
        result = 0
        text = tolower(text)
        for (index_value = 1; index_value <= length(text); index_value++) {
            digit = index("0123456789abcdef", substr(text, index_value, 1)) - 1
            if (digit < 0)
                return -1
            result = result * 16 + digit
        }
        return result
    }
    /^(main|static_bins_data|static_bins_local|static_bins_probe) / {
        current = hex_value($3)
        if (current < 0 || (count > 0 && current < previous))
            exit 1
        previous = current
        count++
    }
    END { if (count != 4) exit 1 }
' "${temporary_dir}/numeric.txt"

grep -Eq 'libfixture[.]a\[archive-member[.]o\]: static_bins_archive_member T ' \
    "${temporary_dir}/archive.txt"

echo "validated nm symbol classes, filters, sorting, and archive-member output"

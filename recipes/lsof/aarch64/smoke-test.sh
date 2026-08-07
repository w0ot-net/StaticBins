#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 LSOF EXPECTED_VERSION" >&2
    exit 1
fi

lsof_binary="$1"
expected_version="$2"
temporary_dir="$(mktemp -d)"
holder_pid=""

cleanup() {
    if [ -n "${holder_pid}" ]; then
        kill "${holder_pid}" 2>/dev/null || true
        wait "${holder_pid}" 2>/dev/null || true
    fi
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_output="$(${lsof_binary} -v 2>&1)"
printf '%s\n' "${version_output}"
if ! printf '%s\n' "${version_output}" | grep -Eq \
    "^[[:space:]]*revision: ${expected_version}$"; then
    echo "error: unexpected lsof version" >&2
    exit 1
fi

held_file="${temporary_dir}/static-bins-lsof-open-file"
: > "${held_file}"
sh -c 'exec 9>"$1"; while :; do sleep 1; done' sh "${held_file}" &
holder_pid="$!"

ready=false
for _attempt in $(seq 1 50); do
    if [ -e "/proc/${holder_pid}/fd/9" ]; then
        ready=true
        break
    fi
    sleep 0.1
done
if [ "${ready}" != "true" ]; then
    echo "error: controlled open-file process did not become ready" >&2
    exit 1
fi

fields="$(timeout 30 "${lsof_binary}" -nP -l -w -a \
    -p "${holder_pid}" -F pfn -- "${held_file}")"
printf '%s\n' "${fields}"
if ! printf '%s\n' "${fields}" | grep -Fxq "p${holder_pid}"; then
    echo "error: lsof did not report the controlled process" >&2
    exit 1
fi
if ! printf '%s\n' "${fields}" | grep -Fxq "n${held_file}"; then
    echo "error: lsof did not report the controlled open file" >&2
    exit 1
fi

echo "validated procfs discovery of a controlled open file"

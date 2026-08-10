#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 BPFTRACE EXPECTED_VERSION" >&2
    exit 1
fi

bpftrace_binary="$1"
expected_version="$2"

version_output="$(${bpftrace_binary} --version 2>&1)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | sed -n '1p')" != \
    "bpftrace v${expected_version}" ]; then
    echo "error: unexpected bpftrace version" >&2
    exit 1
fi

temporary_dir="$(mktemp -d)"
cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

stdout_file="${temporary_dir}/stdout.log"
stderr_file="${temporary_dir}/stderr.log"
if ! timeout 60 "${bpftrace_binary}" -q \
    -e 'BEGIN { printf("static-bins-bpftrace-smoke\n"); exit(); }' \
    >"${stdout_file}" 2>"${stderr_file}"; then
    cat "${stdout_file}" >&2
    cat "${stderr_file}" >&2
    echo "error: bpftrace failed its privileged BEGIN probe" >&2
    exit 1
fi
if ! grep -Fxq 'static-bins-bpftrace-smoke' "${stdout_file}"; then
    cat "${stdout_file}" >&2
    cat "${stderr_file}" >&2
    echo "error: bpftrace did not print its functional smoke marker" >&2
    exit 1
fi

cat "${stdout_file}"
echo "validated bpftrace compilation, BPF loading, and execution"

#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 LTRACE SMOKE_TARGET EXPECTED_VERSION" >&2
    exit 1
fi

ltrace_binary="$1"
smoke_target="$2"
expected_version="$3"
temporary_dir="$(mktemp -d)"

cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_output="$(${ltrace_binary} --version 2>&1)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | sed -n '1p')" != \
    "ltrace ${expected_version}" ]; then
    echo "error: unexpected ltrace version" >&2
    exit 1
fi

trace_file="${temporary_dir}/trace.log"
stdout_file="${temporary_dir}/stdout.log"
stderr_file="${temporary_dir}/stderr.log"
if ! timeout 30 "${ltrace_binary}" -e puts -o "${trace_file}" \
    "${smoke_target}" >"${stdout_file}" 2>"${stderr_file}"; then
    cat "${stdout_file}" >&2
    cat "${stderr_file}" >&2
    cat "${trace_file}" >&2
    echo "error: ltrace failed to trace its dynamically linked child" >&2
    exit 1
fi

if [ "$(cat "${stdout_file}")" != "static-bins-ltrace-marker" ]; then
    echo "error: traced child did not print the expected marker" >&2
    cat "${stdout_file}" >&2
    exit 1
fi
if ! grep -Fq -- '->puts(' "${trace_file}"; then
    echo "error: trace did not contain the expected puts call" >&2
    cat "${trace_file}" >&2
    exit 1
fi
if ! grep -Fq '+++ exited (status 0) +++' "${trace_file}"; then
    echo "error: trace did not record a successful child exit" >&2
    cat "${trace_file}" >&2
    exit 1
fi
if grep -Fq 'Assertion failed' "${stderr_file}"; then
    echo "error: ltrace hit an internal assertion" >&2
    cat "${stderr_file}" >&2
    exit 1
fi

cat "${trace_file}"
echo "validated direct-child musl library-call tracing"

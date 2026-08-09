#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 NETSTAT EXPECTED_VERSION" >&2
    exit 2
fi

netstat_binary="$1"
expected_version="$2"
temporary_dir="$(mktemp -d)"
listener_pid=""

cleanup() {
    if [ -n "${listener_pid}" ]; then
        kill "${listener_pid}" 2>/dev/null || true
        wait "${listener_pid}" 2>/dev/null || true
    fi
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_output="$(${netstat_binary} --version)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | sed -n '1p')" != \
    "net-tools ${expected_version}" ]; then
    echo "error: unexpected netstat version" >&2
    exit 1
fi

timeout 15 /bin/busybox nc -n -l -s 127.0.0.1 -p 32193 \
    > "${temporary_dir}/listener.log" 2>&1 &
listener_pid="$!"
sleep 1
"${netstat_binary}" -lnt > "${temporary_dir}/listeners.txt"
if ! grep -Eq '127[.]0[.]0[.]1:32193[[:space:]].*LISTEN' \
    "${temporary_dir}/listeners.txt"; then
    echo "error: netstat did not report the controlled TCP listener" >&2
    cat "${temporary_dir}/listeners.txt" >&2
    exit 1
fi

"${netstat_binary}" -rn > "${temporary_dir}/routes.txt"
grep -Fq 'Kernel IP routing table' "${temporary_dir}/routes.txt"
grep -Fq 'Destination' "${temporary_dir}/routes.txt"

"${netstat_binary}" -i > "${temporary_dir}/interfaces.txt"
grep -Fq 'Kernel Interface table' "${temporary_dir}/interfaces.txt"
grep -Eq '^lo[[:space:]]' "${temporary_dir}/interfaces.txt"

"${netstat_binary}" -xan > "${temporary_dir}/unix.txt"
grep -Fq 'Active UNIX domain sockets' "${temporary_dir}/unix.txt"
grep -Fq 'Proto RefCnt Flags' "${temporary_dir}/unix.txt"

"${netstat_binary}" -s > "${temporary_dir}/statistics.txt"
grep -Eq '^Ip:' "${temporary_dir}/statistics.txt"
grep -Eq '^Tcp:' "${temporary_dir}/statistics.txt"

echo "validated netstat listener discovery and Linux procfs views"

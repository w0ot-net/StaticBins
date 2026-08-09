#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 NC EXPECTED_VERSION" >&2
    exit 2
fi

nc_binary="$1"
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

version_output="$(${nc_binary} --version)"
printf '%s\n' "${version_output}"
if ! printf '%s\n' "${version_output}" | grep -Fq     "netcat (The GNU Netcat) ${expected_version}"; then
    echo "error: unexpected GNU Netcat version" >&2
    exit 1
fi

printf 'static-bins-nc-tcp\n' > "${temporary_dir}/tcp.expected"
timeout 10 "${nc_binary}" -n -l -p 32191 -w 5     > "${temporary_dir}/tcp.actual" &
listener_pid="$!"
sleep 1
timeout 10 sh -c 'cat "$1" | "$2" -n -c -w 5 127.0.0.1 32191'     sh "${temporary_dir}/tcp.expected" "${nc_binary}" || true
wait "${listener_pid}" 2>/dev/null || true
listener_pid=""
if ! cmp "${temporary_dir}/tcp.expected" "${temporary_dir}/tcp.actual"; then
    echo "error: GNU Netcat TCP loopback payload was not received" >&2
    exit 1
fi

printf 'static-bins-nc-udp\n' > "${temporary_dir}/udp.expected"
timeout 10 "${nc_binary}" -n -u -l -p 32192 -w 5     > "${temporary_dir}/udp.actual" &
listener_pid="$!"
sleep 1
timeout 10 sh -c 'cat "$1" | "$2" -n -u -c -w 2 127.0.0.1 32192'     sh "${temporary_dir}/udp.expected" "${nc_binary}" || true
received=false
for _attempt in $(seq 1 50); do
    if cmp -s "${temporary_dir}/udp.expected" "${temporary_dir}/udp.actual"; then
        received=true
        break
    fi
    sleep 0.1
done
if [ "${received}" != true ]; then
    echo "error: GNU Netcat UDP loopback payload was not received" >&2
    exit 1
fi
kill "${listener_pid}" 2>/dev/null || true
wait "${listener_pid}" 2>/dev/null || true
listener_pid=""

echo "validated GNU Netcat TCP and UDP numeric IPv4 loopback transfers"

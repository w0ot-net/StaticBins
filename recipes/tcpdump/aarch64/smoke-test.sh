#!/bin/sh

set -eu

tcpdump_binary="${1:-/tcpdump}"

if [ ! -x "${tcpdump_binary}" ]; then
    echo "error: tcpdump binary is missing or not executable: ${tcpdump_binary}" >&2
    exit 1
fi

temporary_dir="$(mktemp -d)"
cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

fixture="${temporary_dir}/udp-dns.pcap"
printf '%b' '\324\303\262\241\002\000\004\000\000\000\000\000\000\000\000\000\377\377\000\000\001\000\000\000\001\000\000\000\002\000\000\000\054\000\000\000\054\000\000\000\000\021\042\063\104\125\146\167\210\231\252\273\010\000\105\000\000\036\022\064\100\000\100\021\074\144\300\000\002\001\306\063\144\002\060\071\000\065\000\012\000\000\150\151' > "${fixture}"

version_output="$(${tcpdump_binary} --version 2>&1)"
printf '%s\n' "${version_output}"
printf '%s\n' "${version_output}" | grep -Fq 'tcpdump version 4.99.4'
printf '%s\n' "${version_output}" | grep -Fq 'libpcap version 1.10.4'
if printf '%s\n' "${version_output}" | grep -Eqi 'OpenSSL|LibreSSL|libcap-ng|libsmi'; then
    echo "error: tcpdump reports an intentionally omitted runtime feature" >&2
    exit 1
fi

filter_output="$(${tcpdump_binary} -ddd 'udp and dst port 53' 2>/dev/null)"
if [ "$(printf '%s\n' "${filter_output}" | sed -n '1p')" != 16 ]; then
    echo "error: tcpdump did not compile the expected BPF program" >&2
    printf '%s\n' "${filter_output}" >&2
    exit 1
fi

decoded_output="$(${tcpdump_binary} -nn -tt -r "${fixture}" 'udp and dst port 53' 2>/dev/null)"
expected_output='1.000002 IP 192.0.2.1.12345 > 198.51.100.2.53: domain [length 2 < 12] (invalid)'
if [ "${decoded_output}" != "${expected_output}" ]; then
    echo "error: tcpdump produced unexpected offline decode output" >&2
    printf 'expected: %s\nactual:   %s\n' "${expected_output}" "${decoded_output}" >&2
    exit 1
fi
printf '%s\n' "${decoded_output}"

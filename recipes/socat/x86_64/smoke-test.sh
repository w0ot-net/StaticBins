#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 SOCAT EXPECTED_VERSION" >&2
    exit 1
fi

socat_binary="$1"
expected_version="$2"
temporary_dir="$(mktemp -d)"
server_pid=""

cleanup_server() {
    if [ -n "${server_pid}" ]; then
        kill "${server_pid}" 2>/dev/null || true
        wait "${server_pid}" 2>/dev/null || true
        server_pid=""
    fi
}
cleanup() {
    cleanup_server
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_output="$(${socat_binary} -V 2>&1)"
printf '%s\n' "${version_output}"
if ! printf '%s\n' "${version_output}" | grep -Eq \
    "^socat version ${expected_version} on "; then
    echo "error: unexpected socat version" >&2
    exit 1
fi

run_relay_test() {
    label="$1"
    listen_address="$2"
    connect_address="$3"
    payload="$4"
    output_file="${temporary_dir}/${label}.out"
    log_file="${temporary_dir}/${label}.log"

    "${socat_binary}" "${listen_address}" EXEC:/bin/cat \
        > /dev/null 2> "${log_file}" &
    server_pid="$!"

    relay_ok=false
    for _attempt in $(seq 1 50); do
        if ! kill -0 "${server_pid}" 2>/dev/null; then
            break
        fi
        if printf '%s' "${payload}" | timeout 2 "${socat_binary}" - \
            "${connect_address}" > "${output_file}" 2>/dev/null &&
            [ "$(cat "${output_file}")" = "${payload}" ]; then
            relay_ok=true
            break
        fi
        sleep 0.1
    done

    cleanup_server
    if [ "${relay_ok}" != "true" ]; then
        echo "error: ${label} relay failed" >&2
        cat "${log_file}" >&2
        exit 1
    fi
    echo "validated ${label} relay"
}

tcp_port=$((20000 + ($$ % 10000)))
tls_port=$((40000 + ($$ % 10000)))
unix_socket="${temporary_dir}/relay.sock"

run_relay_test tcp \
    "TCP4-LISTEN:${tcp_port},bind=127.0.0.1,reuseaddr,fork" \
    "TCP4:127.0.0.1:${tcp_port}" \
    "static-bins-socat-tcp-$$"

run_relay_test unix \
    "UNIX-LISTEN:${unix_socket},fork" \
    "UNIX-CONNECT:${unix_socket}" \
    "static-bins-socat-unix-$$"

libressl-openssl req -x509 -newkey rsa:2048 -nodes \
    -subj /CN=localhost -days 1 \
    -keyout "${temporary_dir}/server.key" \
    -out "${temporary_dir}/server.crt" >/dev/null 2>&1
run_relay_test tls \
    "OPENSSL-LISTEN:${tls_port},bind=127.0.0.1,reuseaddr,fork,cert=${temporary_dir}/server.crt,key=${temporary_dir}/server.key,verify=0" \
    "OPENSSL:127.0.0.1:${tls_port},verify=0" \
    "static-bins-socat-tls-$$"

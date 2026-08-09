#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 CURL EXPECTED_VERSION" >&2
    exit 2
fi

curl_binary="$1"
expected_version="$2"
for command_name in awk grep libressl mktemp sed sleep tail timeout tr; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: curl smoke test requires ${command_name}" >&2
        exit 1
    fi
done
temporary_dir="$(mktemp -d)"
server_pid=""
cleanup() {
    if [ -n "${server_pid}" ]; then
        kill "${server_pid}" 2>/dev/null || true
        wait "${server_pid}" 2>/dev/null || true
    fi
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_output="$(${curl_binary} --version)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | sed -n '1p' | awk '{print $2}')" != \
    "${expected_version}" ]; then
    echo "error: unexpected curl version" >&2
    exit 1
fi
protocols="$(printf '%s\n' "${version_output}" | sed -n 's/^Protocols: //p')"
if [ "${protocols}" != "file http https" ]; then
    echo "error: unexpected curl protocol surface: ${protocols}" >&2
    exit 1
fi
features="$(printf '%s\n' "${version_output}" | sed -n 's/^Features: //p')"
for feature in AsynchDNS HTTPS-proxy IPv6 Largefile SSL UnixSockets libz; do
    if ! printf '%s\n' "${features}" | tr ' ' '\n' | grep -Fxq "${feature}"; then
        echo "error: curl feature is missing: ${feature}" >&2
        exit 1
    fi
done
for omitted in brotli HTTP2 HTTP3 IDN PSL zstd; do
    if printf '%s\n' "${features}" | tr ' ' '\n' | grep -Fxq "${omitted}"; then
        echo "error: omitted curl feature is present: ${omitted}" >&2
        exit 1
    fi
done

libressl req -new -newkey rsa:2048 -x509 -nodes -days 1 \
    -subj '/CN=127.0.0.1' \
    -addext 'subjectAltName=IP:127.0.0.1' \
    -keyout "${temporary_dir}/key.pem" \
    -out "${temporary_dir}/cert.pem" >/dev/null 2>&1

port=32443
(
    cd "${temporary_dir}"
    tail -f /dev/null |
        timeout 30 libressl s_server -quiet -www -accept "${port}" \
        -tls1_2 \
        -cert "${temporary_dir}/cert.pem" -key "${temporary_dir}/key.pem"
) > "${temporary_dir}/server.log" 2>&1 &
server_pid="$!"

fetch_test_page() {
    output_file="$1"
    shift
    set +e
    "${curl_binary}" --silent --show-error --fail --http1.0 --tls-max 1.2 \
        --noproxy '*' --connect-timeout 1 --max-time 5 "$@" \
        "https://127.0.0.1:${port}/" -o "${output_file}" \
        2> "${temporary_dir}/fetch.err"
    fetch_status=$?
    set -e

    # LibreSSL s_server sends its complete status page, then omits close_notify.
    # Accept that fixture-specific EOF only when the complete page arrived.
    if [ "${fetch_status}" -ne 0 ] &&
        { [ "${fetch_status}" -ne 56 ] ||
          ! grep -Fxq 'curl: (56) Connection closed abruptly' \
            "${temporary_dir}/fetch.err"; }; then
        return 1
    fi
    grep -Fq '</HTML>' "${output_file}"
}

ready=false
attempt=0
while [ "${attempt}" -lt 20 ]; do
    if fetch_test_page "${temporary_dir}/ready.out" --insecure; then
        ready=true
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done
if [ "${ready}" != true ]; then
    echo "error: local TLS server did not become ready" >&2
    cat "${temporary_dir}/fetch.err" >&2
    cat "${temporary_dir}/server.log" >&2
    exit 1
fi

set +e
"${curl_binary}" --silent --show-error --fail --http1.0 --tls-max 1.2 \
    --noproxy '*' --connect-timeout 1 --max-time 5 \
    "https://127.0.0.1:${port}/" -o /dev/null \
    2> "${temporary_dir}/untrusted.err"
untrusted_status=$?
set -e
if [ "${untrusted_status}" -ne 60 ]; then
    echo "error: curl did not reject the unrecognized certificate as expected" >&2
    cat "${temporary_dir}/untrusted.err" >&2
    exit 1
fi
if ! fetch_test_page "${temporary_dir}/downloaded.txt" \
    --cacert "${temporary_dir}/cert.pem"; then
    echo "error: curl could not authenticate and fetch from the local TLS server" >&2
    cat "${temporary_dir}/fetch.err" >&2
    exit 1
fi

echo "validated curl TLS verification and loopback HTTPS transfer"

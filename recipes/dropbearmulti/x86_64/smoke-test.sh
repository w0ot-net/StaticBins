#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 DROPBEARMULTI EXPECTED_VERSION" >&2
    exit 2
fi

dropbearmulti="$1"
expected_version="$2"
temporary_dir="$(mktemp -d)"
server_auth_dir="/root/.static-bins-dropbear-smoke.$$"
server_pid=""

cleanup() {
    if [ -n "${server_pid}" ]; then
        kill "${server_pid}" 2>/dev/null || true
        wait "${server_pid}" 2>/dev/null || true
    fi
    rm -rf -- "${temporary_dir}" "${server_auth_dir}"
}
trap cleanup EXIT HUP INT TERM

client_version="$(${dropbearmulti} dbclient -V 2>&1)"
server_version="$(${dropbearmulti} dropbear -V 2>&1)"
if [ "${client_version}" != "Dropbear v${expected_version}" ] ||
    [ "${server_version}" != "Dropbear v${expected_version}" ]; then
    echo "error: unexpected Dropbear client or server version" >&2
    exit 1
fi

set +e
multi_usage="$(${dropbearmulti} 2>&1)"
multi_status=$?
set -e
if [ "${multi_status}" -eq 0 ] ||
    ! printf '%s\n' "${multi_usage}" | grep -Fxq "Dropbear SSH multi-purpose v${expected_version}"; then
    echo "error: unexpected dropbearmulti dispatch usage" >&2
    exit 1
fi
for required_role in \
    "'dropbear' - the Dropbear server" \
    "'dbclient' or 'ssh' - the Dropbear client" \
    "'dropbearkey' or 'ssh-keygen' - the key generator" \
    "'dropbearconvert' - the key converter"; do
    if ! printf '%s\n' "${multi_usage}" | grep -Fxq "${required_role}"; then
        echo "error: missing Dropbear multi-call role: ${required_role}" >&2
        exit 1
    fi
done
if printf '%s\n' "${multi_usage}" | grep -Fq "'scp' - secure copy"; then
    echo "error: scp unexpectedly entered dropbearmulti" >&2
    exit 1
fi

expected_kex='sntrup761x25519-sha512
sntrup761x25519-sha512@openssh.com
mlkem768x25519-sha256
curve25519-sha256
curve25519-sha256@libssh.org
ecdh-sha2-nistp521
ecdh-sha2-nistp384
ecdh-sha2-nistp256
diffie-hellman-group14-sha256'
expected_sig='ssh-ed25519
sk-ssh-ed25519@openssh.com
ecdsa-sha2-nistp256
ecdsa-sha2-nistp384
ecdsa-sha2-nistp521
sk-ecdsa-sha2-nistp256@openssh.com
rsa-sha2-256'
expected_cipher='chacha20-poly1305@openssh.com
aes256-ctr
aes128-ctr'
expected_mac='hmac-sha2-256'
expected_compress='none'

assert_algorithms() {
    role="$1"
    kind="$2"
    expected="$3"
    actual_file="${temporary_dir}/${role}-${kind}.actual"
    expected_file="${temporary_dir}/${role}-${kind}.expected"
    "${dropbearmulti}" "${role}" -Q "${kind}" > "${actual_file}"
    printf '%s\n' "${expected}" > "${expected_file}"
    if ! cmp "${expected_file}" "${actual_file}"; then
        echo "error: ${role} ${kind} algorithm profile drifted" >&2
        exit 1
    fi
}

for role in dbclient dropbear; do
    assert_algorithms "${role}" kex "${expected_kex}"
    assert_algorithms "${role}" sig "${expected_sig}"
    assert_algorithms "${role}" cipher "${expected_cipher}"
    assert_algorithms "${role}" mac "${expected_mac}"
    assert_algorithms "${role}" compress "${expected_compress}"
done

host_key="${temporary_dir}/host-ed25519"
client_key="${temporary_dir}/client-ed25519"
converted_key="${temporary_dir}/client-openssh"
roundtrip_key="${temporary_dir}/client-roundtrip"
"${dropbearmulti}" dropbearkey -t ed25519 -f "${host_key}" >/dev/null
"${dropbearmulti}" dropbearkey -t ed25519 -f "${client_key}" >/dev/null
chmod 0600 "${host_key}" "${client_key}"

"${dropbearmulti}" dropbearkey -y -f "${client_key}" \
    > "${temporary_dir}/client-public.txt"
awk '/^ssh-ed25519 / { print $1 " " $2; found = 1; exit } END { if (!found) exit 1 }' \
    "${temporary_dir}/client-public.txt" > "${temporary_dir}/client-public.normalized"

"${dropbearmulti}" dropbearconvert dropbear openssh \
    "${client_key}" "${converted_key}"
"${dropbearmulti}" dropbearconvert openssh dropbear \
    "${converted_key}" "${roundtrip_key}"
chmod 0600 "${converted_key}" "${roundtrip_key}"
"${dropbearmulti}" dropbearkey -y -f "${roundtrip_key}" \
    > "${temporary_dir}/roundtrip-public.txt"
awk '/^ssh-ed25519 / { print $1 " " $2; found = 1; exit } END { if (!found) exit 1 }' \
    "${temporary_dir}/roundtrip-public.txt" > "${temporary_dir}/roundtrip-public.normalized"
cmp "${temporary_dir}/client-public.normalized" \
    "${temporary_dir}/roundtrip-public.normalized"

mkdir -m 0700 "${server_auth_dir}" "${temporary_dir}/client-home"
install -m 0600 "${temporary_dir}/client-public.normalized" \
    "${server_auth_dir}/authorized_keys"

timeout 40 "${dropbearmulti}" dropbear -F -E -s -m \
    -p 127.0.0.1:32195 \
    -P "${temporary_dir}/dropbear.pid" \
    -r "${host_key}" \
    -D "${server_auth_dir}" \
    > "${temporary_dir}/server.log" 2>&1 &
server_pid="$!"

ready=false
attempt=0
while [ "${attempt}" -lt 50 ]; do
    if [ -s "${temporary_dir}/dropbear.pid" ] && kill -0 "${server_pid}" 2>/dev/null; then
        ready=true
        break
    fi
    sleep 0.1
    attempt=$((attempt + 1))
done
if [ "${ready}" != true ]; then
    echo "error: Dropbear server did not become ready" >&2
    cat "${temporary_dir}/server.log" >&2
    exit 1
fi

if ! HOME="${temporary_dir}/client-home" timeout 20 \
    "${dropbearmulti}" dbclient -q -y -T \
        -i "${client_key}" -p 32195 root@127.0.0.1 \
        "printf 'dropbear-loopback-ok\\n'" \
        > "${temporary_dir}/remote-command.out" \
        2> "${temporary_dir}/client.log"; then
    echo "error: Dropbear loopback SSH client failed" >&2
    cat "${temporary_dir}/client.log" >&2
    cat "${temporary_dir}/server.log" >&2
    exit 1
fi
if ! grep -Fxq 'dropbear-loopback-ok' "${temporary_dir}/remote-command.out" ||
    [ ! -s "${temporary_dir}/client-home/.ssh/known_hosts" ]; then
    echo "error: Dropbear remote command or temporary host-key acceptance failed" >&2
    cat "${temporary_dir}/remote-command.out" >&2
    cat "${temporary_dir}/client.log" >&2
    exit 1
fi

kill "${server_pid}" 2>/dev/null || true
wait "${server_pid}" 2>/dev/null || true
server_pid=""

echo "validated Dropbear roles, algorithms, key conversion, and loopback public-key SSH"

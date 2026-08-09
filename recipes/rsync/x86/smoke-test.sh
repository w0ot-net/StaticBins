#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 RSYNC EXPECTED_VERSION" >&2
    exit 2
fi

rsync_binary="$1"
expected_version="$2"
temporary_dir="$(mktemp -d)"
daemon_pid=""

cleanup() {
    if [ -n "${daemon_pid}" ]; then
        kill "${daemon_pid}" 2>/dev/null || true
        wait "${daemon_pid}" 2>/dev/null || true
    fi
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_output="$(${rsync_binary} --version)"
if ! printf '%s\n' "${version_output}" | grep -Fq \
    "rsync  version ${expected_version}  protocol version 32"; then
    echo "error: unexpected rsync version or protocol" >&2
    exit 1
fi

mkdir -p "${temporary_dir}/local-source/nested" "${temporary_dir}/local-dest"
printf 'initial payload\n' > "${temporary_dir}/local-source/data.txt"
printf 'nested payload\n' > "${temporary_dir}/local-source/nested/item.txt"
chmod 0640 "${temporary_dir}/local-source/data.txt"
ln "${temporary_dir}/local-source/data.txt" \
    "${temporary_dir}/local-source/data-hardlink.txt"
ln -s nested/item.txt "${temporary_dir}/local-source/data-symlink.txt"

"${rsync_binary}" -aH "${temporary_dir}/local-source/" \
    "${temporary_dir}/local-dest/"
cmp "${temporary_dir}/local-source/data.txt" "${temporary_dir}/local-dest/data.txt"
test "$(readlink "${temporary_dir}/local-dest/data-symlink.txt")" = nested/item.txt
test "$(stat -c %i "${temporary_dir}/local-dest/data.txt")" = \
    "$(stat -c %i "${temporary_dir}/local-dest/data-hardlink.txt")"
test "$(stat -c %a "${temporary_dir}/local-dest/data.txt")" = 640

printf 'updated payload with changed size\n' > "${temporary_dir}/local-source/data.txt"
printf 'delete me\n' > "${temporary_dir}/local-dest/obsolete.txt"
"${rsync_binary}" -aH --delete "${temporary_dir}/local-source/" \
    "${temporary_dir}/local-dest/"
grep -Fxq 'updated payload with changed size' "${temporary_dir}/local-dest/data.txt"
test ! -e "${temporary_dir}/local-dest/obsolete.txt"
test "$(stat -c %i "${temporary_dir}/local-dest/data.txt")" = \
    "$(stat -c %i "${temporary_dir}/local-dest/data-hardlink.txt")"

mkdir -p "${temporary_dir}/daemon-source/nested" "${temporary_dir}/daemon-dest"
printf 'daemon nested payload\n' > "${temporary_dir}/daemon-source/nested/item.txt"
: > "${temporary_dir}/daemon-source/repetitive.txt"
counter=0
while [ "${counter}" -lt 512 ]; do
    printf 'compressible rsync daemon payload line %s\n' "${counter}" \
        >> "${temporary_dir}/daemon-source/repetitive.txt"
    counter=$((counter + 1))
done
chmod 0777 "${temporary_dir}/daemon-dest"

config_file="${temporary_dir}/rsyncd.conf"
{
    printf 'pid file = %s\n' "${temporary_dir}/rsyncd.pid"
    printf 'lock file = %s\n' "${temporary_dir}/rsyncd.lock"
    printf 'log file = %s\n' "${temporary_dir}/rsyncd.log"
    printf 'use chroot = no\n'
    printf 'uid = 0\n'
    printf 'gid = 0\n'
    printf '[receive]\n'
    printf '    path = %s\n' "${temporary_dir}/daemon-dest"
    printf '    read only = no\n'
    printf '    hosts allow = 127.0.0.1\n'
} > "${config_file}"

timeout 30 "${rsync_binary}" --daemon --no-detach --address=127.0.0.1 \
    --port=32194 --config="${config_file}" &
daemon_pid="$!"
ready=false
attempt=0
while [ "${attempt}" -lt 50 ]; do
    if timeout 2 "${rsync_binary}" --contimeout=1 \
        rsync://127.0.0.1:32194/ > /dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 0.1
    attempt=$((attempt + 1))
done
if [ "${ready}" != true ]; then
    echo "error: rsync daemon did not become ready" >&2
    exit 1
fi

timeout 20 "${rsync_binary}" -az "${temporary_dir}/daemon-source/" \
    rsync://127.0.0.1:32194/receive/
cmp "${temporary_dir}/daemon-source/repetitive.txt" \
    "${temporary_dir}/daemon-dest/repetitive.txt"
cmp "${temporary_dir}/daemon-source/nested/item.txt" \
    "${temporary_dir}/daemon-dest/nested/item.txt"

kill "${daemon_pid}" 2>/dev/null || true
wait "${daemon_pid}" 2>/dev/null || true
daemon_pid=""

echo "validated rsync local incremental/archive behavior and compressed daemon transfer"

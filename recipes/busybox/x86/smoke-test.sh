#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 BUSYBOX EXPECTED_VERSION EXPECTED_APPLETS" >&2
    exit 2
fi

busybox_binary="$1"
expected_version="$2"
expected_applets="$3"
temporary_dir="$(mktemp -d)"

cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_line="$("${busybox_binary}" | "${busybox_binary}" sed -n '1p')"
printf '%s\n' "${version_line}"
if ! printf '%s\n' "${version_line}" | grep -Fq "BusyBox v${expected_version}"; then
    echo "error: unexpected BusyBox version" >&2
    exit 1
fi

"${busybox_binary}" --list | LC_ALL=C "${busybox_binary}" sort > "${temporary_dir}/actual-applets.txt"
if ! "${busybox_binary}" cmp "${expected_applets}" "${temporary_dir}/actual-applets.txt"; then
    echo "error: BusyBox applet membership differs from expected-applets.txt" >&2
    exit 1
fi

"${busybox_binary}" ash -eu -c '
    bb="$1"
    root="$2"

    "${bb}" mkdir -p "${root}/source" "${root}/restored"
    "${bb}" printf "alpha\nbeta\n" > "${root}/source/input.txt"
    "${bb}" cp "${root}/source/input.txt" "${root}/source/copy.txt"
    "${bb}" mv "${root}/source/input.txt" "${root}/source/moved.txt"
    "${bb}" ln -s moved.txt "${root}/source/link.txt"

    "${bb}" find "${root}/source" -type f |
        "${bb}" sed "s#${root}/source/##" |
        "${bb}" sort > "${root}/files.actual"
    "${bb}" printf "copy.txt\nmoved.txt\n" > "${root}/files.expected"
    "${bb}" cmp "${root}/files.expected" "${root}/files.actual"

    "${bb}" grep -qx alpha "${root}/source/copy.txt"
    "${bb}" sed "s/beta/gamma/" "${root}/source/copy.txt" |
        "${bb}" awk "NR == 2 && \$1 == \"gamma\" { found = 1 } END { exit !found }"

    digest="$("${bb}" sha256sum "${root}/source/copy.txt" | "${bb}" cut -d " " -f 1)"
    test "${digest}" = e49c81e2d2f84e259d40e2fb8192f3bcd198b355184845d76d8f58807d0d78ee

    "${bb}" tar -C "${root}/source" -cf "${root}/archive.tar" moved.txt link.txt
    "${bb}" tar -C "${root}/restored" -xf "${root}/archive.tar"
    "${bb}" cmp "${root}/source/moved.txt" "${root}/restored/moved.txt"
    test "$("${bb}" readlink "${root}/restored/link.txt")" = moved.txt
' ash "${busybox_binary}" "${temporary_dir}"

echo "validated BusyBox applet inventory and representative multi-call behavior"

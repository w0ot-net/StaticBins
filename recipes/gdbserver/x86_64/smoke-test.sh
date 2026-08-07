#!/bin/sh

set -eu

if [ "$#" -ne 4 ]; then
    echo "usage: $0 GDBSERVER EXPECTED_VERSION RSP_CLIENT_SOURCE TARGET_SOURCE" >&2
    exit 1
fi

gdbserver="$1"
expected_version="$2"
rsp_client_source="$3"
target_source="$4"

version_output="$(${gdbserver} --version)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | sed -n '1p')" != \
    "GNU gdbserver (GDB) ${expected_version}" ]; then
    echo "error: unexpected gdbserver version" >&2
    exit 1
fi

cc -O2 -Wall -Wextra -Werror -o /tmp/rsp-smoke "${rsp_client_source}"
cc -O2 -Wall -Wextra -Werror -o /tmp/smoke-target "${target_source}"
timeout 90 /tmp/rsp-smoke "${gdbserver}" /tmp/smoke-target

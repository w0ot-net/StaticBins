#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 STRACE EXPECTED_VERSION EXPECTED_OPTIONAL_FEATURES" >&2
    exit 1
fi

strace_binary="$1"
expected_version="$2"
expected_optional_features="$3"
temporary_dir="$(mktemp -d)"

cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_output="$(${strace_binary} --version 2>&1)"
printf '%s\n' "${version_output}"
if ! printf '%s\n' "${version_output}" | grep -Fqx \
    "strace -- version ${expected_version}"; then
    echo "error: unexpected strace version" >&2
    exit 1
fi
if ! printf '%s\n' "${version_output}" | grep -Fqx \
    "Optional features enabled: ${expected_optional_features}"; then
    echo "error: unexpected strace optional feature profile" >&2
    exit 1
fi

cat > "${temporary_dir}/tracee.c" <<'EOF'
#include <fcntl.h>
#include <sys/syscall.h>
#include <unistd.h>

static const char marker[] = "static-bins-strace-marker\n";

int
main(int argc, char **argv)
{
    if (argc != 2)
        return 64;
    long fd = syscall(SYS_openat, AT_FDCWD, argv[1],
                      O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0)
        return 65;
    if (syscall(SYS_write, fd, marker, sizeof(marker) - 1) !=
        (long) (sizeof(marker) - 1))
        return 66;
    syscall(SYS_close, fd);
    syscall(SYS_exit_group, 0);
    return 67;
}
EOF
cc -O2 "${temporary_dir}/tracee.c" -o "${temporary_dir}/tracee"

trace_file="${temporary_dir}/trace.log"
output_file="${temporary_dir}/tracee.out"
if ! timeout 30 "${strace_binary}" -qq -o "${trace_file}" \
    -e trace=openat,write,exit_group \
    "${temporary_dir}/tracee" "${output_file}"; then
    echo "error: strace failed to trace its direct child" >&2
    cat "${trace_file}" >&2
    exit 1
fi

printf '%s\n' 'static-bins-strace-marker' > "${temporary_dir}/expected.out"
if ! cmp -s "${temporary_dir}/expected.out" "${output_file}"; then
    echo "error: traced child did not produce the expected file" >&2
    exit 1
fi
if ! grep -Eq '^openat\(AT_FDCWD, .*tracee[.]out.*, O_WRONLY\|O_CREAT\|O_TRUNC, 0600\) = [0-9]+$' \
    "${trace_file}"; then
    echo "error: trace did not contain the expected openat syscall" >&2
    cat "${trace_file}" >&2
    exit 1
fi
if ! grep -Fq 'write(' "${trace_file}" ||
    ! grep -Fq 'static-bins-strace-marker\n' "${trace_file}"; then
    echo "error: trace did not contain the expected write syscall and marker" >&2
    cat "${trace_file}" >&2
    exit 1
fi
if ! grep -Eq '^exit_group\(0\)[[:space:]]+= ' "${trace_file}"; then
    echo "error: trace did not contain the expected successful exit_group syscall" >&2
    cat "${trace_file}" >&2
    exit 1
fi

cat "${trace_file}"
echo "validated direct-child ptrace syscall decoding"

#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 4 ]]; then
    echo "usage: $0 GDBSERVER VM_SMOKE SMOKE_TARGET KERNEL" >&2
    exit 1
fi

readonly GDBSERVER="$1"
readonly VM_SMOKE="$2"
readonly SMOKE_TARGET="$3"
readonly KERNEL="$4"

for input in "${GDBSERVER}" "${VM_SMOKE}" "${SMOKE_TARGET}" "${KERNEL}"; do
    if [[ ! -f "${input}" ]]; then
        echo "error: missing x86 VM smoke input: ${input}" >&2
        exit 1
    fi
done

temporary_dir="$(mktemp -d)"
cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

initramfs_root="${temporary_dir}/root"
mkdir -p "${initramfs_root}/dev" "${initramfs_root}/proc"
install -m 0755 "${GDBSERVER}" "${initramfs_root}/gdbserver"
install -m 0755 "${VM_SMOKE}" "${initramfs_root}/init"
install -m 0755 "${SMOKE_TARGET}" "${initramfs_root}/smoke-target"

initramfs="${temporary_dir}/initramfs.cpio.gz"
(
    cd "${initramfs_root}"
    find . -print0 \
        | LC_ALL=C sort -z \
        | cpio --null --create --format=newc --owner=0:0 --reproducible \
            2>/dev/null
) | gzip -n > "${initramfs}"

vm_log="${temporary_dir}/qemu.log"
if ! timeout 90 qemu-system-i386 \
    -machine pc \
    -cpu qemu32 \
    -m 256M \
    -kernel "${KERNEL}" \
    -initrd "${initramfs}" \
    -append "console=ttyS0 rdinit=/init panic=-1" \
    -display none \
    -monitor none \
    -nodefaults \
    -serial stdio \
    -no-reboot \
    > "${vm_log}" 2>&1; then
    cat "${vm_log}" >&2
    echo "error: x86 full-system smoke VM failed" >&2
    exit 1
fi
if ! grep -Fq 'STATIC_BINS_GDBSERVER_SMOKE_OK' "${vm_log}"; then
    cat "${vm_log}" >&2
    echo "error: x86 VM did not report a successful RSP exchange" >&2
    exit 1
fi
grep -E '^(Attached|Remote debugging|Killing all inferiors|validated full-system|STATIC_BINS_)' \
    "${vm_log}"

#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 6 ]]; then
    echo "usage: $0 ARCHITECTURE LTRACE VM_SMOKE SMOKE_TARGET MUSL_LOADER KERNEL" >&2
    exit 1
fi

readonly ARCHITECTURE="$1"
readonly LTRACE="$2"
readonly VM_SMOKE="$3"
readonly SMOKE_TARGET="$4"
readonly MUSL_LOADER="$5"
readonly KERNEL="$6"

case "${ARCHITECTURE}" in
    aarch64)
        readonly LOADER_NAME="ld-musl-aarch64.so.1"
        qemu=(qemu-system-aarch64 -machine virt -cpu cortex-a72)
        console="ttyAMA0"
        ;;
    armv7)
        readonly LOADER_NAME="ld-musl-armhf.so.1"
        qemu=(qemu-system-arm -machine virt,highmem=off -cpu cortex-a15)
        console="ttyAMA0"
        ;;
    x86)
        readonly LOADER_NAME="ld-musl-i386.so.1"
        qemu=(qemu-system-i386 -machine pc -cpu qemu32)
        console="ttyS0"
        ;;
    *)
        echo "error: unsupported ltrace VM architecture: ${ARCHITECTURE}" >&2
        exit 2
        ;;
esac
readonly console

for input in \
    "${LTRACE}" "${VM_SMOKE}" "${SMOKE_TARGET}" "${MUSL_LOADER}" \
    "${KERNEL}"; do
    if [[ ! -f "${input}" ]]; then
        echo "error: missing ${ARCHITECTURE} VM smoke input: ${input}" >&2
        exit 1
    fi
done

temporary_dir="$(mktemp -d)"
cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

initramfs_root="${temporary_dir}/root"
mkdir -p \
    "${initramfs_root}/dev" "${initramfs_root}/lib" \
    "${initramfs_root}/proc"
install -m 0755 "${LTRACE}" "${initramfs_root}/ltrace"
install -m 0755 "${VM_SMOKE}" "${initramfs_root}/init"
install -m 0755 "${SMOKE_TARGET}" "${initramfs_root}/smoke-target"
install -m 0755 "${MUSL_LOADER}" "${initramfs_root}/lib/${LOADER_NAME}"

initramfs="${temporary_dir}/initramfs.cpio.gz"
(
    cd "${initramfs_root}"
    find . -print0 \
        | LC_ALL=C sort -z \
        | cpio --null --create --format=newc --owner=0:0 --reproducible \
            2>/dev/null
) | gzip -n > "${initramfs}"

vm_log="${temporary_dir}/qemu.log"
if ! timeout 90 "${qemu[@]}" \
    -m 256M \
    -kernel "${KERNEL}" \
    -initrd "${initramfs}" \
    -append "console=${console} rdinit=/init panic=-1" \
    -display none \
    -monitor none \
    -nodefaults \
    -serial stdio \
    -no-reboot \
    > "${vm_log}" 2>&1; then
    cat "${vm_log}" >&2
    echo "error: ${ARCHITECTURE} full-system ltrace smoke VM failed" >&2
    exit 1
fi
if ! grep -Fq 'STATIC_BINS_LTRACE_SMOKE_OK' "${vm_log}"; then
    cat "${vm_log}" >&2
    echo "error: ${ARCHITECTURE} VM did not report successful library-call tracing" >&2
    exit 1
fi
grep -E '^(validated full-system|STATIC_BINS_)' "${vm_log}"

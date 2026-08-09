#!/bin/sh

set -eu

build_dir=/build/binutils-build
cd "${build_dir}"

for build_target in objdump readelf nm-new; do
    output_name="${build_target}"
    if [ "${build_target}" = nm-new ]; then
        output_name=nm
    fi
    rm -f "binutils/${build_target}" "binutils/.libs/${build_target}"
    if ! make -C binutils V=1 \
        LDFLAGS="-all-static -Wl,-Map,/out/${output_name}-link.map" \
        "${build_target}" > "/out/${output_name}-relink.log" 2>&1; then
        cat "/out/${output_name}-relink.log" >&2
        exit 1
    fi
    tail -n 3 "/out/${output_name}-relink.log"
done

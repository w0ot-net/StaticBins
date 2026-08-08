# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY aarch64/source.lock /usr/local/share/static_bins/ltrace/source.lock
COPY aarch64/sources /usr/local/share/static_bins/ltrace/sources
COPY aarch64/licenses /usr/local/share/licenses/ltrace
COPY aarch64/musl-main-link-map.patch /usr/local/share/static_bins/ltrace/musl-main-link-map.patch
COPY aarch64/aarch64-musl-pid-t.patch /usr/local/share/static_bins/ltrace/aarch64-musl-pid-t.patch
COPY aarch64/build-in-container.sh /usr/local/bin/build-static-ltrace

RUN /usr/local/bin/build-static-ltrace

COPY aarch64/smoke-target.c vm-smoke.c /tmp/static-bins-smoke/

RUN cc -O0 -fno-builtin -no-pie \
        /tmp/static-bins-smoke/smoke-target.c -o /out/smoke-target \
    && cc -O2 -static -no-pie -s \
        /tmp/static-bins-smoke/vm-smoke.c -o /out/vm-smoke \
    && cp -L /lib/ld-musl-aarch64.so.1 /out/ld-musl.so.1

FROM scratch AS artifact

COPY --from=builder /out/ltrace /ltrace
COPY --from=builder /out/smoke-target /smoke-target
COPY --from=builder /out/vm-smoke /vm-smoke
COPY --from=builder /out/ld-musl.so.1 /ld-musl.so.1

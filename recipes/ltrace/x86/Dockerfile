# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY x86/source.lock /usr/local/share/static_bins/ltrace/source.lock
COPY x86/sources /usr/local/share/static_bins/ltrace/sources
COPY x86/licenses /usr/local/share/licenses/ltrace
COPY x86/musl-main-link-map.patch /usr/local/share/static_bins/ltrace/musl-main-link-map.patch
COPY x86/build-in-container.sh /usr/local/bin/build-static-ltrace

RUN /usr/local/bin/build-static-ltrace

COPY x86/smoke-target.c vm-smoke.c /tmp/static-bins-smoke/

RUN cc -O0 -fno-builtin -no-pie -march=i686 -msse2 -mfpmath=sse \
        /tmp/static-bins-smoke/smoke-target.c -o /out/smoke-target \
    && cc -O2 -static -no-pie -s -march=i686 -msse2 -mfpmath=sse \
        /tmp/static-bins-smoke/vm-smoke.c -o /out/vm-smoke \
    && cp -L /lib/ld-musl-i386.so.1 /out/ld-musl.so.1

FROM scratch AS artifact

COPY --from=builder /out/ltrace /ltrace
COPY --from=builder /out/smoke-target /smoke-target
COPY --from=builder /out/vm-smoke /vm-smoke
COPY --from=builder /out/ld-musl.so.1 /ld-musl.so.1

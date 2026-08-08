# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/ltrace/source.lock
COPY sources /usr/local/share/static_bins/ltrace/sources
COPY licenses /usr/local/share/licenses/ltrace
COPY musl-main-link-map.patch /usr/local/share/static_bins/ltrace/musl-main-link-map.patch
COPY build-in-container.sh /usr/local/bin/build-static-ltrace

RUN /usr/local/bin/build-static-ltrace

COPY smoke-target.c /tmp/static-bins-smoke/smoke-target.c

RUN cc -O0 -fno-builtin -no-pie \
        /tmp/static-bins-smoke/smoke-target.c -o /out/smoke-target

FROM scratch AS artifact

COPY --from=builder /out/ltrace /ltrace
COPY --from=builder /out/smoke-target /smoke-target

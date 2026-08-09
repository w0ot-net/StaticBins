# syntax=docker/dockerfile:1
ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8
ENV BUILD_JOBS=${BUILD_JOBS}

COPY source.lock /usr/local/share/static_bins/busybox/source.lock
COPY sources /usr/local/share/static_bins/busybox/sources
COPY busybox.config /usr/local/share/static_bins/busybox/busybox.config
COPY expected-applets.txt /usr/local/share/static_bins/busybox/expected-applets.txt
COPY licenses /usr/local/share/licenses/busybox
COPY validate-elf.sh /usr/local/bin/validate-busybox-elf
COPY build-in-container.sh /usr/local/bin/build-static-busybox

RUN /usr/local/bin/build-static-busybox

FROM scratch AS artifact
COPY --from=builder /out/busybox /busybox

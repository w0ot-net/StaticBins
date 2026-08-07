# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/strace/source.lock
COPY sources /usr/local/share/static_bins/strace/sources
COPY licenses /usr/local/share/licenses/strace
COPY build-in-container.sh /usr/local/bin/build-static-strace

RUN /usr/local/bin/build-static-strace

FROM scratch AS artifact

COPY --from=builder /out/strace /strace

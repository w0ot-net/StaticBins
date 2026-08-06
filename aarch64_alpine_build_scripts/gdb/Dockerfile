# syntax=docker/dockerfile:1

ARG BUILDER_IMAGE=alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
FROM ${BUILDER_IMAGE} AS builder

ARG GDB_VERSION=17.2
ARG GDB_SHA256=1c036c0d72e4b3d1fb5c94c88632add6f9d76f4d7c4d2ea793c12a9f19a3228c
ARG BUILD_JOBS=8

COPY build-in-container.sh /usr/local/bin/build-static-gdb

RUN /usr/local/bin/build-static-gdb

FROM scratch
ARG GDB_VERSION=17.2

LABEL org.opencontainers.image.source="https://github.com/w0ot-net/static_bins" \
      org.opencontainers.image.description="Static AArch64 GDB binary artifact" \
      org.opencontainers.image.version="${GDB_VERSION}" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

COPY --from=builder /out/gdb /gdb
ENTRYPOINT ["/gdb"]

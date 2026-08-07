# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/gdb/source.lock
COPY licenses /usr/local/share/licenses/gdb
COPY build-in-container.sh /usr/local/bin/build-static-gdb

RUN /usr/local/bin/build-static-gdb

FROM scratch

LABEL org.opencontainers.image.source="https://github.com/w0ot-net/static_bins" \
      org.opencontainers.image.description="Static AArch64 GDB binary artifact" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

COPY --from=builder /out/gdb /gdb
COPY source.lock /usr/share/licenses/gdb/source.lock
COPY licenses /usr/share/licenses/gdb
ENTRYPOINT ["/gdb"]

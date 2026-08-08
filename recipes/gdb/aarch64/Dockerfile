# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/gdb/source.lock
COPY sources /usr/local/share/static_bins/gdb/sources
COPY licenses /usr/local/share/licenses/gdb
COPY build-in-container.sh /usr/local/bin/build-static-gdb
COPY --chmod=0755 validate-elf.sh /usr/local/bin/validate-static-pie-gdb

RUN /usr/local/bin/build-static-gdb

FROM scratch AS artifact

COPY --from=builder /out/gdb /gdb

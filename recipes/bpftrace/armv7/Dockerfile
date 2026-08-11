# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/bpftrace/source.lock
COPY target.lock /usr/local/share/static_bins/bpftrace/target.lock
COPY sources /usr/local/share/static_bins/bpftrace/sources
COPY patches /usr/local/share/static_bins/bpftrace/patches
COPY licenses /usr/local/share/licenses/bpftrace
COPY validate-elf.sh /usr/local/bin/validate-static-bpftrace
COPY build-in-container.sh /usr/local/bin/build-static-bpftrace

RUN --mount=type=cache,id=static_bins-bpftrace-armv7-build,target=/build-cache,sharing=locked \
    /usr/local/bin/build-static-bpftrace

FROM scratch AS artifact

COPY --from=builder /out/bpftrace /bpftrace

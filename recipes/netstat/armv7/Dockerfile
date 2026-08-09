# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/netstat/source.lock
COPY sources /usr/local/share/static_bins/netstat/sources
COPY patches /usr/local/share/static_bins/netstat/patches
COPY netstat.config.make /usr/local/share/static_bins/netstat/netstat.config.make
COPY licenses /usr/local/share/licenses/netstat
COPY validate-elf.sh /usr/local/bin/validate-netstat-elf
COPY build-in-container.sh /usr/local/bin/build-static-netstat

RUN /usr/local/bin/build-static-netstat

FROM scratch AS artifact

COPY --from=builder /out/netstat /netstat

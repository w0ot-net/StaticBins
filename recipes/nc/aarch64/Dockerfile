# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/nc/source.lock
COPY sources /usr/local/share/static_bins/nc/sources
COPY patches /usr/local/share/static_bins/nc/patches
COPY licenses /usr/local/share/licenses/nc
COPY validate-elf.sh /usr/local/bin/validate-nc-elf
COPY build-in-container.sh /usr/local/bin/build-static-nc

RUN /usr/local/bin/build-static-nc

FROM scratch AS artifact

COPY --from=builder /out/nc /nc

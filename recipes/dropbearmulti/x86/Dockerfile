# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8
ENV BUILD_JOBS=${BUILD_JOBS}

COPY source.lock /usr/local/share/static_bins/dropbearmulti/source.lock
COPY sources /usr/local/share/static_bins/dropbearmulti/sources
COPY localoptions.h /usr/local/share/static_bins/dropbearmulti/localoptions.h
COPY licenses /usr/local/share/licenses/dropbearmulti
COPY validate-elf.sh /usr/local/bin/validate-dropbearmulti-elf
COPY build-in-container.sh /usr/local/bin/build-static-dropbearmulti

RUN /usr/local/bin/build-static-dropbearmulti

FROM scratch AS artifact

COPY --from=builder /out/dropbearmulti /dropbearmulti

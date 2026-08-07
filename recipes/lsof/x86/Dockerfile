# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/lsof/source.lock
COPY sources /usr/local/share/static_bins/lsof/sources
COPY licenses /usr/local/share/licenses/lsof
COPY build-in-container.sh /usr/local/bin/build-static-lsof

RUN /usr/local/bin/build-static-lsof

FROM scratch AS artifact

COPY --from=builder /out/lsof /lsof

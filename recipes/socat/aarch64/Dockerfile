# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/socat/source.lock
COPY sources /usr/local/share/static_bins/socat/sources
COPY licenses /usr/local/share/licenses/socat
COPY build-in-container.sh /usr/local/bin/build-static-socat

RUN /usr/local/bin/build-static-socat

FROM scratch AS artifact

COPY --from=builder /out/socat /socat

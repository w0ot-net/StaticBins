# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/gdbserver/source.lock
COPY sources /usr/local/share/static_bins/gdbserver/sources
COPY licenses /usr/local/share/licenses/gdbserver
COPY build-in-container.sh /usr/local/bin/build-static-gdbserver

RUN /usr/local/bin/build-static-gdbserver

FROM scratch AS artifact

COPY --from=builder /out/gdbserver /gdbserver

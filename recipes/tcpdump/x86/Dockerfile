# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/tcpdump/source.lock
COPY sources /usr/local/share/static_bins/tcpdump/sources
COPY licenses /usr/local/share/licenses/tcpdump
COPY smoke-test.sh /usr/local/bin/smoke-test-tcpdump
COPY build-in-container.sh /usr/local/bin/build-static-tcpdump

RUN /usr/local/bin/build-static-tcpdump

FROM scratch AS artifact

COPY --from=builder /out/tcpdump /tcpdump

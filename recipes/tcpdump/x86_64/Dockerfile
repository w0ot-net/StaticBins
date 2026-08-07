# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/tcpdump/source.lock
COPY licenses /usr/local/share/licenses/tcpdump
COPY smoke-test.sh /usr/local/bin/smoke-test-tcpdump
COPY build-in-container.sh /usr/local/bin/build-static-tcpdump

RUN /usr/local/bin/build-static-tcpdump

FROM scratch

LABEL org.opencontainers.image.source="https://github.com/w0ot-net/static_bins" \
      org.opencontainers.image.description="Static x86-64 tcpdump binary artifact" \
      org.opencontainers.image.licenses="BSD-3-Clause"

COPY --from=builder /out/tcpdump /tcpdump
COPY source.lock /usr/share/licenses/tcpdump/source.lock
COPY licenses /usr/share/licenses/tcpdump
ENTRYPOINT ["/tcpdump"]

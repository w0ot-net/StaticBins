# syntax=docker/dockerfile:1

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8
ENV BUILD_JOBS=${BUILD_JOBS}

COPY build-in-container.sh /usr/local/bin/build-curl
COPY source.lock target.lock validate-elf.sh /usr/local/share/static_bins/curl/
COPY sources/ /usr/local/share/static_bins/curl/sources/
COPY licenses/ /usr/local/share/licenses/curl/

RUN /usr/local/bin/build-curl

FROM scratch AS artifact
COPY --from=builder /out/curl /curl

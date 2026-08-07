# syntax=docker/dockerfile:1

ARG ALPINE_IMAGE
FROM ${ALPINE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/w0ot-net/static_bins" \
      org.opencontainers.image.description="Reusable AArch64 Alpine toolchain for static_bins build recipes"

COPY builder-packages.lock /tmp/builder-packages.lock

RUN apk add --no-cache $(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' /tmp/builder-packages.lock) \
    && rm -f /tmp/builder-packages.lock

WORKDIR /workspace
CMD ["/bin/bash"]

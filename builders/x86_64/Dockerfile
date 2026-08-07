# syntax=docker/dockerfile:1

ARG ALPINE_IMAGE
FROM ${ALPINE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/w0ot-net/static_bins" \
      org.opencontainers.image.description="Reusable x86-64 Alpine toolchain for static_bins build recipes"

COPY packages.lock /tmp/packages.lock

RUN apk add --no-cache $(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' /tmp/packages.lock) \
    && rm -f /tmp/packages.lock

WORKDIR /workspace
CMD ["/bin/sh"]
